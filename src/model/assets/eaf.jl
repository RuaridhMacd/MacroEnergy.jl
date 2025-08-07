struct Eaf{T} <: AbstractAsset
    id::AssetId
    eaf_transform::Transformation
    crudesteel_edge::Edge{CrudeSteel}
    elec_edge::Edge{Electricity}
    feedstock_edge::Edge{T} # feedstock can be dri or steel scrap
    naturalgas_edge::Edge{NaturalGas}
    metcoal_edge::Edge{MetCoal}
    co2_edge::Edge{CO2}
end


function default_data(t::Type{Eaf}, id=missing, style="full")
    if style == "full"
        return full_default_data(t, id)
    else
        return simple_default_data(t, id)
    end
end

function full_default_data(::Type{Eaf}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :transforms => @transform_data(
            :timedata => "Electricity",
            :constraints => Dict{Symbol, Bool}(
                :BalanceConstraint => true,
            ),
            :electricity_consumption => 0.0,
            :feedstock_consumption => 0.0,
            :naturalgas_consumption => 0.0,
            :metcoal_consumption => 0.0,
            :emission_rate => 0.0
        ),
        :edges => Dict{Symbol,Any}(
            :crudesteel_edge => @edge_data(
                :commodity => "CrudeSteel",
                :has_capacity => true,
                :can_retire => true,
                :can_expand => true,
                :can_retire => true,
                :constraints => Dict{Symbol, Bool}(
                    :CapacityConstraint => true,
                ),
            ),
            :feedstock_edge => @edge_data(
                :commodity => missing,
            ),
            :elec_edge => @edge_data(
                :commodity => "Electricity"
            ),
            :naturalgas_edge => @edge_data(
                :commodity => "NaturalGas"
            ),
            :metcoal_edge => @edge_data(
                :commodity => "MetCoal"
            ),
            :co2_edge => @edge_data(
                :commodity => "CO2"
            )
        ),
    )
end


function simple_default_data(::Type{Eaf}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :location => missing,
        :can_expand => true,
        :can_retire => true,
        :existing_capacity => 0.0,
        :electricity_consumption => 0.0,
        :feedstock_consumption => 0.0,
        :naturalgas_consumption => 0.0,
        :metcoal_consumption => 0.0,
        :emission_rate => 0.0,
        :investment_cost => 0.0,
        :fixed_om_cost => 0.0,
        :variable_om_cost => 0.0,
    )
end

function set_commodity!(::Type{Eaf}, commodity::Type{<:Commodity}, data::AbstractDict{Symbol,Any})
    edge_keys = [:feedstock_edge]
    if haskey(data, :feedstock_commodity)
        data[:feedstock_commodity] = string(commodity)
    end
    if haskey(data, :edges)
        for edge_key in edge_keys
            if haskey(data[:edges], edge_key)
                if haskey(data[:edges][edge_key], :commodity)
                    data[:edges][edge_key][:commodity] = string(commodity)
                end
            end
        end
    end
end

function make(asset_type::Type{Eaf}, data::AbstractDict{Symbol,Any}, system::System)
    id = AssetId(data[:id])
    @setup_data(asset_type, data, id)

    eaf_key = :transforms
    transform_data = process_data(data[eaf_key])
    eaf_transform = Transformation(;
        id = Symbol(id, "_", eaf_key),
        timedata = system.time_data[Symbol(transform_data[:timedata])],
        constraints = get(transform_data, :constraints, [BalanceConstraint()]),
    )
    # electricity edge 

    elec_edge_key = :elec_edge
    @process_data(
        elec_edge_data, 
        data[:edges][elec_edge_key], 
        [
            (data[:edges][elec_edge_key], key),
            (data[:edges][elec_edge_key], Symbol("elec_", key)),
            (data, Symbol("elec_", key)),
        ]
    )
    @start_vertex(
        elec_start_node,
        elec_edge_data,
        Electricity,
        [(elec_edge_data, :start_vertex), (data, :location)],
    )
    elec_end_node = eaf_transform 
    elec_edge = Edge(
        Symbol(id, "_", elec_edge_key),
        elec_edge_data,
        system.time_data[:Electricity],
        Electricity,
        elec_start_node,
        elec_end_node,
    )
    elec_edge.unidirectional = true

    # feedstock edge

    feedstock_edge_key = :feedstock_edge
    @process_data(
        feedstock_edge_data, 
        data[:edges][feedstock_edge_key], 
        [
            (data[:edges][feedstock_edge_key], key),
            (data[:edges][feedstock_edge_key], Symbol("feedstock_", key)),
            (data, Symbol("feedstock_", key)),
        ]
    )
    commodity_symbol = Symbol(feedstock_edge_data[:commodity])
    commodity = commodity_types()[commodity_symbol]
    @start_vertex(
        feedstock_start_node,
        feedstock_edge_data,
        commodity,
        [(feedstock_edge_data, :start_vertex), (data, :location)],
    )
    feedstock_end_node = eaf_transform
    feedstock_edge = Edge(
        Symbol(id, "_", feedstock_edge_key),
        feedstock_edge_data,
        system.time_data[commodity_symbol],
        commodity,
        feedstock_start_node,
        feedstock_end_node,
    )
    feedstock_edge.unidirectional = true;

    # natural gas edge

    naturalgas_edge_key = :naturalgas_edge
    @process_data(
        naturalgas_edge_data,
        data[:edges][naturalgas_edge_key],
        [
            (data[:edges][naturalgas_edge_key], key),
            (data[:edges][naturalgas_edge_key], Symbol("naturalgas_", key)),
            (data, Symbol("naturalgas_", key)),
        ]
    )
    @start_vertex(
        naturalgas_start_node,
        naturalgas_edge_data,
        NaturalGas,
        [(naturalgas_edge_data, :start_vertex), (data, :location)],
    )
    naturalgas_end_node = eaf_transform

    naturalgas_edge = Edge(
        Symbol(id, "_", naturalgas_edge_key),
        naturalgas_edge_data,
        system.time_data[:NaturalGas],
        NaturalGas,
        naturalgas_start_node,
        naturalgas_end_node,
    )
    naturalgas_edge.unidirectional = true;

    # metalurgical coal edge

    metcoal_edge_key = :metcoal_edge
    @process_data(
        metcoal_edge_data, 
        data[:edges][metcoal_edge_key], 
        [
            (data[:edges][metcoal_edge_key], key),
            (data[:edges][metcoal_edge_key], Symbol("metcoal_", key)),
            (data, Symbol("metcoal_", key)),
        ]
    )
    @start_vertex(
        metcoal_start_node,
        metcoal_edge_data,
        MetCoal,
        [(metcoal_edge_data, :start_vertex), (data, :location)],
    )
    metcoal_end_node = eaf_transform
    metcoal_edge = Edge(
        Symbol(id, "_", metcoal_edge_key),
        metcoal_edge_data,
        system.time_data[:MetCoal],
        MetCoal,
        metcoal_start_node,
        metcoal_end_node,
    )
    metcoal_edge.unidirectional = true;

    # crude steel edge
    crudesteel_edge_key = :crudesteel_edge
    @process_data(
        crudesteel_edge_data, 
        data[:edges][crudesteel_edge_key], 
        [
            (data[:edges][crudesteel_edge_key], key),
            (data[:edges][crudesteel_edge_key], Symbol("crudesteel_", key)),
            (data, Symbol("crudesteel_", key)),
            (data, key),
        ]
    )
    crudesteel_start_node = eaf_transform
    @end_vertex(
        crudesteel_end_node,
        crudesteel_edge_data,
        CrudeSteel,
        [(crudesteel_edge_data, :end_vertex), (data, :location)],
    )
    crudesteel_edge = Edge(
        Symbol(id, "_", crudesteel_edge_key),
        crudesteel_edge_data,
        system.time_data[:CrudeSteel],
        CrudeSteel,
        crudesteel_start_node,
        crudesteel_end_node,
    )
    crudesteel_edge.unidirectional = get(crudesteel_edge_data, :unidirectional, true)

    # co2 edge
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
    co2_start_node = eaf_transform
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
    co2_edge.constraints = Vector{AbstractTypeConstraint}()
    co2_edge.unidirectional = true;
    co2_edge.has_capacity = false;

    # stochiometry
    eaf_transform.balance_data = Dict(
        :electricity_consumption => Dict(
            crudesteel_edge.id => get(transform_data, :electricity_consumption, 1.0),
            elec_edge.id => 1.0,
        ),
        :feedstock_consumption => Dict(
            crudesteel_edge.id => get(transform_data, :feedstock_consumption, 1.0),
            feedstock_edge.id => 1.0
        ),
        :naturalgas_consumption => Dict(
            crudesteel_edge.id => get(transform_data, :feedstock_consumption, 1.0),
            naturalgas_edge.id => 1.0,
        ),
        :metcoal_consumption => Dict(
            crudesteel_edge.id => get(transform_data, :metcoal_consumption, 0.0),
            metcoal_edge.id => 1.0,
        ),
        :emissions => Dict(
            crudesteel_edge.id => get(transform_data, :emission_rate, 0.0),
            co2_edge.id => -1.0,
        ) 
    )


    return Eaf(id,
            eaf_transform,
            crudesteel_edge,
            elec_edge,
            feedstock_edge,
            naturalgas_edge,
            metcoal_edge,
            co2_edge
        )
end
