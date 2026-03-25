struct DownstreamUse{T} <: AbstractAsset
    id::AssetId
    enduse_transform::Transformation
    demand_node::Node{<:T}
    incoming_edge::Edge{<:T}
    demand_edge::Edge{<:T}
    co2_edge::Edge{<:CO2}
end

DownstreamUse(id::AssetId, enduse_transform::Transformation, demand_node::Node{T}, incoming_edge::Edge{T}, demand_edge::Edge{T}, co2_edge::Edge{<:CO2}) where T<:Commodity =
    DownstreamUse{T}(id, enduse_transform, demand_node, incoming_edge, demand_edge, co2_edge)

function default_data(t::Type{DownstreamUse}, id=missing, style="full")
    if style == "full"
        return full_default_data(t, id)
    else
        return simple_default_data(t, id)
    end
end

function full_default_data(::Type{DownstreamUse}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :transforms => @transform_data(
            :timedata => "Electricity",
            :constraints => Dict{Symbol, Bool}(
                :BalanceConstraint => true,
            ),
            :emission_rate => 0.0,
        ),
        :nodes => @node_data(
            :commodity => "Electricity",
            
        ),
        :edges => Dict{Symbol, Any}(
            :incoming_edge => @edge_data(
                :commodity => "Electricity",
            ),
            :demand_edge => @edge_data(
                :commodity => "Electricity",
            ),
            :co2_edge => @edge_data(
                :commodity => "CO2",
                :co2_sink => missing,
            ),
        ),

    )
end

function simple_default_data(::Type{DownstreamUse}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :location => missing,
        :co2_sink => missing,
        :emission_rate => 0.0,
        :commodity => "Electricity",
        :demand => Vector{Float64}(),
        :price_supply => OrderedDict{Symbol,Any}(),
        :max_supply => OrderedDict{Symbol,Any}(),
        :price_nsd => [0.0],
        :max_nsd => [0.0],
    )
end

function set_commodity!(::Type{DownstreamUse}, commodity::Type{<:Commodity}, data::AbstractDict{Symbol,Any})
    data[:commodity] = string(commodity)
    data[:nodes][:commodity] = string(commodity)
    data[:edges][:incoming_edge][:commodity] = string(commodity)
    data[:edges][:demand_edge][:commodity] = string(commodity)
    data[:transforms][:timedata] = string(commodity)
    return
end

function make(asset_type::Type{DownstreamUse}, data::AbstractDict{Symbol,Any}, system::System)
    id = AssetId(data[:id])
    location = as_symbol_or_missing(get(data, :location, missing))

    @setup_data(asset_type, data, id)

    top_level_commodity = get(data, :commodity, missing)
    top_commodity_symbol = ismissing(top_level_commodity) ? missing : Symbol(top_level_commodity)

    downstreamemissions_key = :transforms
    @process_data(
        transform_data, 
        data[downstreamemissions_key], 
        [
            (data[downstreamemissions_key], key),
            (data[downstreamemissions_key], Symbol("transform_", key)),
            (data, Symbol("transform_", key)),
            (data, key),
        ]
    )
    commodity_symbol = ismissing(top_commodity_symbol) ? Symbol(transform_data[:timedata]) : top_commodity_symbol
    enduse_transform = Transformation(;
        id = Symbol(id, "_", downstreamemissions_key),
        timedata = system.time_data[commodity_symbol],
        location = location,
        constraints = transform_data[:constraints],
    )

    downstreamdemand_key = :nodes
    @process_data(
        demand_node_data, 
        data[downstreamdemand_key], 
        [
            (data[downstreamdemand_key], key),
            (data[downstreamdemand_key], Symbol("demand_", key)),
            (data, Symbol("demand_", key)),
            (data, key),
        ]
    )
    commodity_symbol = ismissing(top_commodity_symbol) ? Symbol(demand_node_data[:commodity]) : top_commodity_symbol
    commodity = commodity_types()[commodity_symbol]
    demand_node_data[:id] = Symbol(id, "_", downstreamdemand_key)
    demand_node = node = Node(data, system.time_data[commodity_symbol], commodity)
    demand_node.constraints = get(data, :constraints, Vector{AbstractTypeConstraint}())
    setup_balance_data!(demand_node, data)

    incoming_edge_key = :incoming_edge
    @process_data(
        incoming_edge_data, 
        data[:edges][incoming_edge_key], 
        [
            (data[:edges][incoming_edge_key], key),
            (data[:edges][incoming_edge_key], Symbol("incoming_edge_", key)),
            (data, Symbol("incoming_edge_", key)),
        ]
    )
    commodity_symbol = ismissing(top_commodity_symbol) ? Symbol(incoming_edge_data[:commodity]) : top_commodity_symbol
    commodity = commodity_types()[commodity_symbol]
    @start_vertex(
        incoming_edge_start_node,
        incoming_edge_data,
        commodity,
        [(incoming_edge_data, :start_vertex), (data, :location)],
    )
    incoming_edge_end_node = enduse_transform
    incoming_edge = Edge(
        Symbol(id, "_", incoming_edge_key),
        incoming_edge_data,
        system.time_data[commodity_symbol],
        commodity,
        incoming_edge_start_node,
        incoming_edge_end_node,
    )

    demand_edge_key = :demand_edge
    @process_data(
        demand_edge_data, 
        data[:edges][demand_edge_key], 
        [
            (data[:edges][demand_edge_key], key),
            (data[:edges][demand_edge_key], Symbol("demand_edge_", key)),
            (data, Symbol("demand_edge_", key)),
        ]
    )
    commodity_symbol = ismissing(top_commodity_symbol) ? Symbol(demand_edge_data[:commodity]) : top_commodity_symbol
    commodity = commodity_types()[commodity_symbol]
    demand_edge_start_node = enduse_transform
    demand_edge_end_node = demand_node
    demand_edge = Edge(
        Symbol(id, "_", demand_edge_key),
        demand_edge_data,
        system.time_data[commodity_symbol],
        commodity,
        demand_edge_start_node,
        demand_edge_end_node,
    )

    co2_edge_key = :co2_edge
    @process_data(
        co2_edge_data, 
        data[:edges][co2_edge_key], 
        [
            (data[:edges][co2_edge_key], key),
            (data[:edges][co2_edge_key], Symbol("co2_", key)),
            (data, Symbol("co2_", key)),
        ]
    )
    co2_start_node = enduse_transform
    @end_vertex(
        co2_end_node,
        co2_edge_data,
        CO2,
        [(co2_edge_data, :end_vertex), (data, :co2_sink), (data, :location)],
    )
    co2_edge = Edge(
        Symbol(id, "_", co2_edge_key),
        co2_edge_data,
        system.time_data[:CO2],
        CO2,
        co2_start_node,
        co2_end_node,
    )

    enduse_transform.balance_data = Dict(
        :demand => Dict(
            incoming_edge.id => 1.0,
            demand_edge.id => 1.0
        ),
        :emissions => Dict(
            incoming_edge.id => get(transform_data, :emission_rate, 0.0),
            co2_edge.id => 1.0
        )
    )

    return DownstreamUse(id, enduse_transform, demand_node, incoming_edge, demand_edge, co2_edge) 
end
