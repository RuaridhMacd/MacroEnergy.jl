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
