Base.@kwdef mutable struct ProblemInstance
    id::Symbol
    static_system::StaticSystem
    spec::ProblemSpec
    model::Model = Model()
    node_state::Dict{Int,NodeLocalState} = Dict{Int,NodeLocalState}()
    unidirectional_edge_state::Dict{Int,EdgeLocalState} = Dict{Int,EdgeLocalState}()
    bidirectional_edge_state::Dict{Int,EdgeLocalState} = Dict{Int,EdgeLocalState}()
    unit_commitment_edge_state::Dict{Int,EdgeLocalState} = Dict{Int,EdgeLocalState}()
    transformation_state::Dict{Int,TransformationLocalState} = Dict{Int,TransformationLocalState}()
    storage_state::Dict{Int,StorageLocalState} = Dict{Int,StorageLocalState}()
    long_duration_storage_state::Dict{Int,StorageLocalState} = Dict{Int,StorageLocalState}()
    update_map::UpdateMap = UpdateMap()
    reassembly_map::ReassemblyMap = ReassemblyMap()
end

function ProblemInstance(static_system::StaticSystem, spec_input::Union{Nothing,ProblemSpec}; id::Symbol=:problem)
    spec = normalize_problem_spec(static_system, spec_input)
    return ProblemInstance(
        id = id,
        static_system = static_system,
        spec = spec,
    )
end
