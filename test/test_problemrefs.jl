module TestProblemRefs

using Test
using MacroEnergy

import MacroEnergy:
    StaticSystem,
    TimeData,
    Problem,
    component,
    component_ref_key,
    charge_edge,
    discharge_edge,
    end_vertex,
    get_component_refs,
    get_period_to_subproblem_mapping,
    get_periods,
    id,
    load_case,
    period_index,
    slice_system,
    slice_timedata,
    spillage_edge,
    start_vertex,
    temporal_benders_problem_specs,
    time_interval

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

@testset "ProblemSpec-driven Benders slicing" begin
    source_time_data = TimeData{MacroEnergy.Electricity}(;
        time_interval = 1:1:6,
        hours_per_timestep = 1,
        period_index = 4,
        subperiods = [1:1:3, 4:1:6],
        subperiod_indices = [11, 12],
        subperiod_weights = Dict(11 => 2.0, 12 => 3.0),
        subperiod_map = Dict(1 => 11, 2 => 12),
        total_hours_modeled = 6,
    )
    sliced_time_data = slice_timedata(source_time_data, [4, 5, 6])

    @test collect(sliced_time_data.time_interval) == [4, 5, 6]
    @test sliced_time_data.subperiods == [4:1:6]
    @test sliced_time_data.subperiod_indices == [12]
    @test sliced_time_data.subperiod_weights == Dict(12 => 3.0)
    @test sliced_time_data.subperiod_map == Dict(2 => 12)

    case = load_case(multistage_mono_path)
    systems = StaticSystem.(get_periods(case))
    specs = temporal_benders_problem_specs(systems)
    period_to_subproblem_map, number_of_subproblems = get_period_to_subproblem_mapping(specs)

    @test number_of_subproblems == sum(length(system.time_data[:Electricity].subperiods) for system in systems)
    @test sort(collect(keys(period_to_subproblem_map))) == period_index.(systems)

    spec = specs[1]
    sliced_system = slice_system(systems, spec)
    source_system = systems[1]

    @test period_index(sliced_system) == period_index(source_system)
    @test collect(sliced_system.time_data[:Electricity].time_interval) == spec.time_indices
    @test length(sliced_system.nodes) == length(source_system.nodes)
    @test !isempty(sliced_system.component_lookup)

    node_key = spec.node_keys[1]
    @test component(sliced_system, node_key) !== component(source_system, node_key)
    @test id(component(sliced_system, node_key)) == id(component(source_system, node_key))

    edge_key = spec.unidirectional_edge_keys[1]
    sliced_edge = component(sliced_system, edge_key)
    sliced_vertices = [
        sliced_system.nodes...,
        sliced_system.transformations...,
        sliced_system.storages...,
        sliced_system.long_duration_storages...,
    ]
    @test start_vertex(sliced_edge) in sliced_vertices
    @test end_vertex(sliced_edge) in sliced_vertices

    storage_key = spec.storage_keys[1]
    sliced_storage = component(sliced_system, storage_key)
    @test charge_edge(sliced_storage) in keys(sliced_system.component_lookup)
    @test discharge_edge(sliced_storage) in keys(sliced_system.component_lookup)
    if !isnothing(spillage_edge(sliced_storage))
        @test spillage_edge(sliced_storage) in keys(sliced_system.component_lookup)
    end
end

end
