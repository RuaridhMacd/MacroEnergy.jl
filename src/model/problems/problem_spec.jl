Base.@kwdef struct ProblemSpec
    id::Symbol = :problem
    role::Symbol = :monolithic
    node_indices::Vector{Int} = Int[]
    unidirectional_edge_indices::Vector{Int} = Int[]
    bidirectional_edge_indices::Vector{Int} = Int[]
    unit_commitment_edge_indices::Vector{Int} = Int[]
    transformation_indices::Vector{Int} = Int[]
    storage_indices::Vector{Int} = Int[]
    long_duration_storage_indices::Vector{Int} = Int[]
    time_indices::Vector{Int} = Int[]
    boundaries::Dict{Symbol,Any} = Dict{Symbol,Any}()
    interfaces::Dict{Symbol,Any} = Dict{Symbol,Any}()
    metadata::Dict{Symbol,Any} = Dict{Symbol,Any}()
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

function full_problem_spec(static_system::StaticSystem; id::Symbol=:monolithic, role::Symbol=:monolithic)
    return ProblemSpec(
        id = id,
        role = role,
        node_indices = collect(eachindex(static_system.nodes)),
        unidirectional_edge_indices = collect(eachindex(static_system.unidirectional_edges)),
        bidirectional_edge_indices = collect(eachindex(static_system.bidirectional_edges)),
        unit_commitment_edge_indices = collect(eachindex(static_system.unit_commitment_edges)),
        transformation_indices = collect(eachindex(static_system.transformations)),
        storage_indices = collect(eachindex(static_system.storages)),
        long_duration_storage_indices = collect(eachindex(static_system.long_duration_storages)),
        time_indices = all_time_indices(static_system),
    )
end

normalize_problem_spec(static_system::StaticSystem, ::Nothing) = full_problem_spec(static_system)
normalize_problem_spec(::StaticSystem, spec::ProblemSpec) = spec
