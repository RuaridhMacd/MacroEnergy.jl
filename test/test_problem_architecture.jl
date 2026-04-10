module TestProblemArchitecture

using Test
using JuMP
using MacroEnergy

import MacroEnergy:
    Case,
    ProblemInstance,
    StaticSystem,
    full_problem_spec,
    get_edges,
    get_nodes,
    get_storages,
    get_transformations,
    load_case,
    normalize_problem_spec

function test_problem_architecture()
    case = load_case(joinpath(@__DIR__, "test_small_case"))
    @test case isa Case
    system = case.systems[1]
    static_system = StaticSystem(system)

    @test length(static_system.nodes) == length(get_nodes(system))
    @test length(static_system.unidirectional_edges) +
          length(static_system.bidirectional_edges) +
          length(static_system.unit_commitment_edges) ==
          length(get_edges(system))
    @test length(static_system.storages) + length(static_system.long_duration_storages) ==
          length(get_storages(system))
    @test length(static_system.transformations) == length(get_transformations(system))
    @test length(static_system.assets) == length(system.assets)

    spec = normalize_problem_spec(static_system, nothing)
    full_spec = full_problem_spec(static_system)
    @test spec.role == :monolithic
    @test spec.id == full_spec.id
    @test length(spec.node_indices) == length(static_system.nodes)
    @test length(spec.unidirectional_edge_indices) == length(static_system.unidirectional_edges)
    @test length(spec.bidirectional_edge_indices) == length(static_system.bidirectional_edges)
    @test length(spec.unit_commitment_edge_indices) ==
          length(static_system.unit_commitment_edges)
    @test length(spec.transformation_indices) == length(static_system.transformations)
    @test length(spec.storage_indices) == length(static_system.storages)
    @test length(spec.long_duration_storage_indices) ==
          length(static_system.long_duration_storages)
    @test !isempty(spec.time_indices)

    instance = ProblemInstance(static_system, nothing; id=:monolithic_problem)
    @test instance.id == :monolithic_problem
    @test instance.static_system === static_system
    @test instance.spec.role == spec.role
    @test instance.spec.node_indices == spec.node_indices
    @test instance.spec.unidirectional_edge_indices == spec.unidirectional_edge_indices
    @test instance.spec.bidirectional_edge_indices == spec.bidirectional_edge_indices
    @test instance.spec.unit_commitment_edge_indices == spec.unit_commitment_edge_indices
    @test instance.spec.transformation_indices == spec.transformation_indices
    @test instance.spec.storage_indices == spec.storage_indices
    @test instance.spec.long_duration_storage_indices == spec.long_duration_storage_indices
    @test instance.spec.time_indices == spec.time_indices
    @test instance.model isa Model
end

@testset "Problem Architecture" begin
    test_problem_architecture()
end

end # module TestProblemArchitecture
