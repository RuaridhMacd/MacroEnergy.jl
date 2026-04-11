module TestProblemArchitecture

using Test
using JuMP
using HiGHS
using MacroEnergy

import MacroEnergy:
    apply_planning_solution!,
    build_monolithic_problem_instances,
    build_planning_problem_instances,
    build_temporal_subproblem_bundles,
    Case,
    ProblemInstance,
    StaticSystem,
    full_problem_spec,
    generate_planning_problem,
    get_edges,
    get_nodes,
    get_settings,
    get_storages,
    get_transformations,
    fix_update_instructions,
    initialize_subproblems!,
    load_case,
    normalize_problem_spec,
    problem_spec

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

    custom_spec = problem_spec(
        static_system;
        id=:custom,
        role=:temporal_subproblem,
        time_indices=spec.time_indices[1:1],
        metadata=Dict{Symbol,Any}(:subproblem_index => 1),
    )
    @test custom_spec.id == :custom
    @test custom_spec.role == :temporal_subproblem
    @test length(custom_spec.time_indices) == 1
    @test custom_spec.metadata[:subproblem_index] == 1

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

    instances = build_monolithic_problem_instances(case)
    @test length(instances) == length(case.systems)
    @test instances[1] isa ProblemInstance
    @test instances[1].static_system.data_dirpath == case.systems[1].data_dirpath
    @test instances[1].spec.role == :monolithic
    @test length(instances[1].node_state) == length(instances[1].spec.node_indices)

    planning_instances = build_planning_problem_instances(case)
    @test length(planning_instances) == length(case.systems)
    @test all(instance -> instance.spec.role == :planning, planning_instances)

    subproblem_bundles = build_temporal_subproblem_bundles(case)
    expected_subproblems = sum(length(system.time_data[:Electricity].subperiods) for system in case.systems)
    @test length(subproblem_bundles) == expected_subproblems
    @test subproblem_bundles[1].instance isa ProblemInstance
    @test subproblem_bundles[1].instance.spec.role == :temporal_subproblem
    @test subproblem_bundles[1].instance.spec.metadata[:subproblem_index] == 1
    @test subproblem_bundles[1].system isa typeof(case.systems[1])

    planning_problem = generate_planning_problem(case)
    missing_planning_names = [
        name(v) for v in all_variables(planning_problem)
        if isempty(name(v)) || isnothing(variable_by_name(planning_problem, name(v)))
    ]
    @test isempty(missing_planning_names)

    subproblems, _ = initialize_subproblems!(
        subproblem_bundles,
        Dict(:solver => HiGHS.Optimizer, :attributes => ()),
        get_settings(case),
        false,
        false,
    )
    missing_subproblem_names = [
        variable_name for variable_name in first(subproblems)[:linking_variables_sub]
        if isnothing(variable_by_name(first(subproblems)[:model], variable_name))
    ]
    @test isempty(missing_subproblem_names)

    first_subproblem = first(subproblems)
    first_instance = first_subproblem[:problem_instance]
    initial_fix_updates = fix_update_instructions(first_instance.update_map)
    @test length(initial_fix_updates) == length(first_subproblem[:linking_variables_sub])

    initial_model_id = objectid(first_subproblem[:model])
    planning_values_1 = Dict(variable_name => 0.0 for variable_name in first_subproblem[:linking_variables_sub])
    apply_planning_solution!(first_instance, planning_values_1)
    @test objectid(first_subproblem[:model]) == initial_model_id
    @test all(is_fixed(instruction.ref) for instruction in initial_fix_updates)
    @test all(fix_value(instruction.ref) == 0.0 for instruction in initial_fix_updates)

    planning_values_2 = Dict(variable_name => 1.0 for variable_name in first_subproblem[:linking_variables_sub])
    apply_planning_solution!(first_instance, planning_values_2)
    @test objectid(first_subproblem[:model]) == initial_model_id
    @test all(fix_value(instruction.ref) == 1.0 for instruction in initial_fix_updates)
end

@testset "Problem Architecture" begin
    test_problem_architecture()
end

end # module TestProblemArchitecture
