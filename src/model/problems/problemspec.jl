Base.@kwdef struct ProblemSpec
    id::Symbol = :problem
    node_keys::Vector{ComponentRefKey} = ComponentRefKey[]
    unidirectional_edge_keys::Vector{ComponentRefKey} = ComponentRefKey[]
    bidirectional_edge_keys::Vector{ComponentRefKey} = ComponentRefKey[]
    unit_commitment_edge_keys::Vector{ComponentRefKey} = ComponentRefKey[]
    transformation_keys::Vector{ComponentRefKey} = ComponentRefKey[]
    storage_keys::Vector{ComponentRefKey} = ComponentRefKey[]
    long_duration_storage_keys::Vector{ComponentRefKey} = ComponentRefKey[]
    time_indices::Vector{Int} = Int[]
end

function all_time_indices(static_system::StaticSystem)
    time_indices = reduce(
        union,
        (collect(time_data.time_interval) for time_data in values(static_system.time_data));
        init = Int[],
    )
    sort!(time_indices)
    return time_indices
end

function all_time_indices(static_systems::AbstractVector{StaticSystem})
    time_indices = reduce(union, (all_time_indices(system) for system in static_systems); init = Int[])
    sort!(time_indices)
    return time_indices
end

function component_ref_keys(static_system::StaticSystem, field::Symbol)
    return [
        ComponentRefKey(period_index = period_index(static_system), field = field, index = idx)
        for idx in eachindex(getproperty(static_system, field))
    ]
end

function component_ref_keys(static_systems::AbstractVector{StaticSystem}, field::Symbol)
    return reduce(vcat, (component_ref_keys(system, field) for system in static_systems); init = ComponentRefKey[])
end

function problem_spec(
    static_systems::AbstractVector{StaticSystem};
    id::Symbol=:problem,
    node_keys::Vector{ComponentRefKey}=component_ref_keys(static_systems, :nodes),
    unidirectional_edge_keys::Vector{ComponentRefKey}=component_ref_keys(static_systems, :unidirectional_edges),
    bidirectional_edge_keys::Vector{ComponentRefKey}=component_ref_keys(static_systems, :bidirectional_edges),
    unit_commitment_edge_keys::Vector{ComponentRefKey}=component_ref_keys(static_systems, :unit_commitment_edges),
    transformation_keys::Vector{ComponentRefKey}=component_ref_keys(static_systems, :transformations),
    storage_keys::Vector{ComponentRefKey}=component_ref_keys(static_systems, :storages),
    long_duration_storage_keys::Vector{ComponentRefKey}=component_ref_keys(static_systems, :long_duration_storages),
    time_indices::Vector{Int}=all_time_indices(static_systems),
)
    return ProblemSpec(
        id = id,
        node_keys = copy(node_keys),
        unidirectional_edge_keys = copy(unidirectional_edge_keys),
        bidirectional_edge_keys = copy(bidirectional_edge_keys),
        unit_commitment_edge_keys = copy(unit_commitment_edge_keys),
        transformation_keys = copy(transformation_keys),
        storage_keys = copy(storage_keys),
        long_duration_storage_keys = copy(long_duration_storage_keys),
        time_indices = copy(time_indices),
    )
end

problem_spec(static_system::StaticSystem; kwargs...) =
    problem_spec([static_system]; kwargs...)

full_problem_spec(static_system::StaticSystem; id::Symbol=:problem) =
    problem_spec(static_system; id)

full_problem_spec(static_systems::AbstractVector{StaticSystem}; id::Symbol=:problem) =
    problem_spec(static_systems; id)

function step_range_from_indices(indices)
    sorted_indices = sort(collect(indices))
    isempty(sorted_indices) && error("Cannot create a time slice from empty time indices")
    length(sorted_indices) == 1 && return sorted_indices[1]:1:sorted_indices[1]

    step = sorted_indices[2] - sorted_indices[1]
    all(sorted_indices[i] - sorted_indices[i - 1] == step for i in 2:length(sorted_indices)) ||
        error("Time slices must be representable as a StepRange")
    return sorted_indices[1]:step:sorted_indices[end]
end

function slice_timedata(time_data::TimeData{T}, time_indices) where {T}
    selected = Set(collect(time_indices))
    selected_subperiod_positions = Int[]

    for (idx, subperiod) in enumerate(time_data.subperiods)
        if any(t -> t in selected, subperiod)
            push!(selected_subperiod_positions, idx)
        end
    end

    isempty(selected_subperiod_positions) &&
        error("No subperiods in period $(time_data.period_index) overlap the requested time indices")

    selected_subperiods = time_data.subperiods[selected_subperiod_positions]
    selected_subperiod_indices = time_data.subperiod_indices[selected_subperiod_positions]
    selected_time_interval = step_range_from_indices(Iterators.flatten(selected_subperiods))

    selected_weights = Dict(
        w => time_data.subperiod_weights[w]
        for w in selected_subperiod_indices
        if haskey(time_data.subperiod_weights, w)
    )

    selected_representatives = Set(selected_subperiod_indices)
    selected_subperiod_map = Dict(
        modeled => representative
        for (modeled, representative) in time_data.subperiod_map
        if representative in selected_representatives
    )

    return TimeData{T}(;
        time_interval = selected_time_interval,
        hours_per_timestep = time_data.hours_per_timestep,
        period_index = time_data.period_index,
        subperiods = copy(selected_subperiods),
        subperiod_indices = copy(selected_subperiod_indices),
        subperiod_weights = selected_weights,
        subperiod_map = selected_subperiod_map,
        total_hours_modeled = time_data.total_hours_modeled,
    )
end

function reset_operational_result_fields!(component)
    hasproperty(component, :operation_expr) && setproperty!(component, :operation_expr, Dict{Symbol,Vector{Float64}}())
    hasproperty(component, :flow) && setproperty!(component, :flow, Float64[])
    hasproperty(component, :ucommit) && setproperty!(component, :ucommit, Float64[])
    hasproperty(component, :ustart) && setproperty!(component, :ustart, Float64[])
    hasproperty(component, :ushut) && setproperty!(component, :ushut, Float64[])
    hasproperty(component, :storage_level) && setproperty!(component, :storage_level, Float64[])
    hasproperty(component, :non_served_demand) && setproperty!(component, :non_served_demand, zeros(0, 0))
    hasproperty(component, :supply_flow) && setproperty!(component, :supply_flow, zeros(0, 0))
    hasproperty(component, :policy_budgeting_vars) && setproperty!(component, :policy_budgeting_vars, Dict{Symbol,Any}())
    hasproperty(component, :policy_slack_vars) && setproperty!(component, :policy_slack_vars, Dict{Symbol,Any}())
    hasproperty(component, :policy_budgeting_constraints) && setproperty!(component, :policy_budgeting_constraints, Dict{DataType,Any}())
    return component
end

function copy_component_for_slice(component, sliced_time_data::AbstractDict{Symbol,<:TimeData})
    component_copy = deepcopy(component)
    setproperty!(component_copy, :timedata, component_time_data(component, sliced_time_data))
    reset_operational_result_fields!(component_copy)
    return component_copy
end

function component_time_data(component, sliced_time_data::AbstractDict{Symbol,<:TimeData})
    commodity_symbol = typesymbol(commodity_type(component.timedata))
    return sliced_time_data[commodity_symbol]
end

function selected_component_keys(spec::ProblemSpec, spec_field::Symbol, period::Int)
    return [key for key in getproperty(spec, spec_field) if key.period_index == period]
end

function copy_components_for_slice!(
    lookup::Dict{ComponentRefKey,Int},
    components::Vector,
    source_system::StaticSystem,
    keys::Vector{ComponentRefKey},
    sliced_time_data::AbstractDict{Symbol,<:TimeData},
)
    for key in keys
        push!(components, copy_component_for_slice(component(source_system, key), sliced_time_data))
        lookup[key] = length(components)
    end
    return components
end

function sliced_vertices(system::StaticSystem)
    return AbstractVertex[
        system.nodes...,
        system.transformations...,
        system.storages...,
        system.long_duration_storages...,
    ]
end

function matching_sliced_vertex(system::StaticSystem, vertex::AbstractVertex)
    vertices = sliced_vertices(system)
    vertex_commodity = commodity_type(vertex.timedata)
    idx = findfirst(
        candidate -> id(candidate) == id(vertex) && commodity_type(candidate.timedata) == vertex_commodity,
        vertices,
    )
    isnothing(idx) && error("Vertex $(id(vertex)) is not included in sliced StaticSystem for period $(period_index(system))")
    return vertices[idx]
end

function rewire_edge_endpoints!(edge, sliced_system::StaticSystem)
    edge.start_vertex = matching_sliced_vertex(sliced_system, edge.start_vertex)
    edge.end_vertex = matching_sliced_vertex(sliced_system, edge.end_vertex)
    return edge
end

function rewire_storage_edges!(storage::AbstractStorage, sliced_system::StaticSystem)
    storage.charge_edge = storage_edge_key(sliced_system, storage.charge_edge)
    storage.discharge_edge = storage_edge_key(sliced_system, storage.discharge_edge)
    storage.spillage_edge = storage_edge_key(sliced_system, storage.spillage_edge)
    return storage
end

function slice_system(static_system::StaticSystem, spec::ProblemSpec)
    period = period_index(static_system)
    sliced_time_data = Dict(
        commodity => slice_timedata(time_data, spec.time_indices)
        for (commodity, time_data) in static_system.time_data
    )

    lookup = Dict{ComponentRefKey,Int}()
    nodes = Node[]
    transformations = Transformation[]
    storages = Storage[]
    long_duration_storages = LongDurationStorage[]
    unidirectional_edges = UnidirectionalEdge[]
    bidirectional_edges = BidirectionalEdge[]
    unit_commitment_edges = EdgeWithUC[]

    copy_components_for_slice!(lookup, nodes, static_system, selected_component_keys(spec, :node_keys, period), sliced_time_data)
    copy_components_for_slice!(lookup, transformations, static_system, selected_component_keys(spec, :transformation_keys, period), sliced_time_data)
    copy_components_for_slice!(lookup, storages, static_system, selected_component_keys(spec, :storage_keys, period), sliced_time_data)
    copy_components_for_slice!(lookup, long_duration_storages, static_system, selected_component_keys(spec, :long_duration_storage_keys, period), sliced_time_data)
    copy_components_for_slice!(lookup, unidirectional_edges, static_system, selected_component_keys(spec, :unidirectional_edge_keys, period), sliced_time_data)
    copy_components_for_slice!(lookup, bidirectional_edges, static_system, selected_component_keys(spec, :bidirectional_edge_keys, period), sliced_time_data)
    copy_components_for_slice!(lookup, unit_commitment_edges, static_system, selected_component_keys(spec, :unit_commitment_edge_keys, period), sliced_time_data)

    sliced_system = StaticSystem(
        period_index = period,
        data_dirpath = static_system.data_dirpath,
        settings = static_system.settings,
        commodities = copy(static_system.commodities),
        time_data = sliced_time_data,
        nodes = nodes,
        unidirectional_edges = unidirectional_edges,
        bidirectional_edges = bidirectional_edges,
        unit_commitment_edges = unit_commitment_edges,
        transformations = transformations,
        storages = storages,
        long_duration_storages = long_duration_storages,
        assets = copy(static_system.assets),
        locations = Union{Node,Location}[nodes...],
        component_lookup = lookup,
    )

    for edge in get_edges(sliced_system)
        rewire_edge_endpoints!(edge, sliced_system)
    end
    for storage in get_storages(sliced_system)
        rewire_storage_edges!(storage, sliced_system)
    end

    return sliced_system
end

function slice_system(static_systems::AbstractVector{StaticSystem}, spec::ProblemSpec)
    periods = unique(key.period_index for (_, spec_field) in PROBLEM_COMPONENT_FIELD_PAIRS for key in getproperty(spec, spec_field))
    isempty(periods) && error("Cannot slice a system with a ProblemSpec that contains no component keys")
    length(periods) == 1 || error("slice_system currently supports one period per ProblemSpec")

    system_index = findfirst(system -> period_index(system) == first(periods), static_systems)
    isnothing(system_index) && error("No StaticSystem found for period $(first(periods))")
    return slice_system(static_systems[system_index], spec)
end

function temporal_benders_problem_specs(static_systems::AbstractVector{StaticSystem}; id_prefix::Symbol=:subproblem)
    specs = ProblemSpec[]
    subproblem_index = 0

    for static_system in static_systems
        period = period_index(static_system)
        electricity_time_data = static_system.time_data[:Electricity]
        for subperiod_position in eachindex(electricity_time_data.subperiods)
            subproblem_index += 1
            time_indices = collect(electricity_time_data.subperiods[subperiod_position])
            push!(
                specs,
                problem_spec(
                    static_system;
                    id = Symbol(id_prefix, :_, subproblem_index),
                    time_indices = time_indices,
                ),
            )
        end
    end

    return specs
end

function get_period_to_subproblem_mapping(specs::AbstractVector{ProblemSpec})
    period_to_subproblem_map = Dict{Int,Vector{Int}}()
    for (subproblem_index, spec) in enumerate(specs)
        periods = unique(key.period_index for (_, spec_field) in PROBLEM_COMPONENT_FIELD_PAIRS for key in getproperty(spec, spec_field))
        isempty(periods) && continue
        length(periods) == 1 || error("Each temporal Benders subproblem spec must contain exactly one period")
        push!(get!(period_to_subproblem_map, first(periods), Int[]), subproblem_index)
    end
    return period_to_subproblem_map, length(specs)
end
