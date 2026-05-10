module TestProblemRefs

using Test
using MacroEnergy

import MacroEnergy:
    StaticSystem,
    Problem,
    component,
    component_ref_key,
    get_component_refs,
    get_periods,
    id,
    load_case,
    period_index

const multistage_mono_path = joinpath(@__DIR__, "..", "examples", "electricity_3zone_multistage_mono")

@testset "ProblemRefs period-qualified component identity" begin
    case = load_case(multistage_mono_path)
    systems = StaticSystem.(get_periods(case))
    problem = Problem(systems)

    @testset "Component identity" begin
        @test problem isa Problem
        @test length(problem.spec.node_keys) == sum(length(system.nodes) for system in systems)
        @test length(unique(problem.spec.node_keys)) == length(problem.spec.node_keys)

        first_period_node = systems[1].nodes[1]
        second_period_node = systems[2].nodes[1]

        @test id(first_period_node) == id(second_period_node)

        first_period_key = component_ref_key(problem.refs, first_period_node)
        second_period_key = component_ref_key(problem.refs, second_period_node)

        @test first_period_key != second_period_key
        @test first_period_key.period_index == period_index(first_period_node)
        @test second_period_key.period_index == period_index(second_period_node)
        @test component(systems, first_period_key) === first_period_node
        @test component(systems, second_period_key) === second_period_node
        @test get_component_refs(problem.refs, first_period_key) !== get_component_refs(problem.refs, second_period_key)
    end

    @testset "Linked component refs" begin
        edge = systems[2].unidirectional_edges[1]
        edge_key = component_ref_key(problem.refs, edge)
        edge_refs = get_component_refs(problem.refs, edge_key)

        @test edge_refs.edge.start_vertex_ref.period_index == period_index(edge)
        @test edge_refs.edge.end_vertex_ref.period_index == period_index(edge)

        storage = systems[2].storages[1]
        storage_key = component_ref_key(problem.refs, storage)
        storage_refs = get_component_refs(problem.refs, storage_key)

        @test storage_refs.charge_edge_ref == storage.charge_edge
        @test storage_refs.discharge_edge_ref == storage.discharge_edge
        @test storage_refs.spillage_edge_ref == storage.spillage_edge
        @test storage_refs.charge_edge_ref.period_index == period_index(storage)
    end
end

end
