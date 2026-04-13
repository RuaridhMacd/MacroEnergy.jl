module TestProblemArchitecture

using Test
using JuMP
using HiGHS
using DataFrames
using MacroEnergy

import MacroEnergy:
    apply_planning_solution!,
    build_monolithic_problem_instances,
    build_planning_problem,
    build_planning_problem_instances,
    build_temporal_subproblem_bundles,
    Case,
    capture_planning_solution!,
    create_named_problem_model,
    materialize_planning_solution!,
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
    get_detailed_costs_benders,
    get_fixed_costs_benders,
    get_existing_capacity,
    get_optimal_capacity,
    initialize_subproblems!,
    load_case,
    normalize_problem_spec,
    populate_planning_problem!,
    problem_spec
import MacroEnergy: update_subproblem_solution!

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
    @test !haskey(subproblem_bundles[1], :system)
    first_subproblem_time_data = MacroEnergy.get_primary_time_data(subproblem_bundles[1].instance.static_system)
    @test length(first_subproblem_time_data.subperiods) == 1
    @test length(first_subproblem_time_data.subperiod_indices) == 1

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
    @test !haskey(first_subproblem, :system_local)
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

    update_subproblem_solution!(first_subproblem, (values=planning_values_2,))
    @test any(haskey(state.values, :flow) for state in values(first_instance.unidirectional_edge_state)) ||
          any(haskey(state.values, :flow) for state in values(first_instance.bidirectional_edge_state)) ||
          any(haskey(state.values, :flow) for state in values(first_instance.unit_commitment_edge_state))
    @test any(haskey(state.values, :balance_dual) for state in values(first_instance.node_state))

    planning_model = generate_planning_problem(case)
    @test planning_model isa Model
    planning_bundle = build_planning_problem(case)
    planning_values = Dict(
        name(variable) => 0.0 for variable in all_variables(planning_bundle.model)
        if !isempty(name(variable))
    )
    capture_planning_solution!(planning_bundle.planning_instances, planning_values)

    first_planning_instance = planning_bundle.planning_instances[1]
    @test any(
        state -> get(state.values, :capacity, nothing) isa Number ||
                 get(state.values, :new_capacity, nothing) isa Number,
        values(first_planning_instance.unidirectional_edge_state),
    ) ||
    any(
        state -> get(state.values, :capacity, nothing) isa Number ||
                 get(state.values, :new_capacity, nothing) isa Number,
        values(first_planning_instance.storage_state),
    ) ||
    any(
        state -> get(state.values, :capacity, nothing) isa Number ||
                 get(state.values, :new_capacity, nothing) isa Number,
        values(first_planning_instance.long_duration_storage_state),
    )

    planning_capacity_df = get_optimal_capacity(first_planning_instance)
    @test planning_capacity_df isa DataFrame
    @test !isempty(planning_capacity_df)
    @test all(value -> value isa Float64, planning_capacity_df.value)

    planning_existing_capacity_df = get_existing_capacity(first_planning_instance)
    @test planning_existing_capacity_df isa DataFrame
    @test !isempty(planning_existing_capacity_df)
    @test all(value -> value isa Float64, planning_existing_capacity_df.value)

    planning_fixed_costs = get_fixed_costs_benders(first_planning_instance, get_settings(case))
    @test planning_fixed_costs.discounted isa DataFrame
    @test planning_fixed_costs.undiscounted isa DataFrame

    planning_detailed_costs = get_detailed_costs_benders(
        first_planning_instance,
        DataFrame(zone=String[], type=String[], category=Symbol[], value=Float64[]),
        get_settings(case),
    )
    @test planning_detailed_costs.discounted isa DataFrame
    @test planning_detailed_costs.undiscounted isa DataFrame

    materialize_planning_solution!(planning_bundle.planning_instances)

    first_period_system = case.systems[1]
    @test all(
        value -> value isa Number || value isa AbstractDict || value isa AbstractArray,
        [
            begin
                first_capacity_component = first(vcat(
                    MacroEnergy.edges_with_capacity_variables(get_edges(first_period_system)),
                    get_storages(first_period_system),
                ))
                MacroEnergy.capacity(first_capacity_component)
            end,
            begin
                first_node_with_policy = findfirst(
                    node -> !isempty(MacroEnergy.policy_budgeting_vars(node)),
                    get_nodes(first_period_system),
                )
                isnothing(first_node_with_policy) ? Dict() :
                    MacroEnergy.policy_budgeting_vars(get_nodes(first_period_system)[first_node_with_policy])
            end,
        ],
    )

    fresh_case = load_case(joinpath(@__DIR__, "test_small_case"))
    populated_planning_instance = build_planning_problem_instances(fresh_case)[1]
    populated_planning_model = create_named_problem_model(populated_planning_instance)
    @variable(populated_planning_model, vREF == 1)
    populated_planning_model[:eFixedCost] = AffExpr(0.0)
    populated_planning_model[:eInvestmentFixedCost] = AffExpr(0.0)
    populated_planning_model[:eOMFixedCost] = AffExpr(0.0)
    populate_planning_problem!(populated_planning_instance, populated_planning_model; period_idx=1)
    @test any(
        state -> haskey(state.variables, :capacity) || haskey(state.variables, :new_capacity),
        values(populated_planning_instance.unidirectional_edge_state),
    ) ||
    any(
        state -> haskey(state.variables, :capacity) || haskey(state.variables, :new_capacity),
        values(populated_planning_instance.storage_state),
    ) ||
    any(
        state -> haskey(state.variables, :capacity) || haskey(state.variables, :new_capacity),
        values(populated_planning_instance.long_duration_storage_state),
    )

    @test any(haskey(state.variables, :flow) for state in values(first_instance.unidirectional_edge_state)) ||
          any(haskey(state.variables, :flow) for state in values(first_instance.bidirectional_edge_state)) ||
          any(haskey(state.variables, :flow) for state in values(first_instance.unit_commitment_edge_state))
    @test any(haskey(state.expressions, :operation_expr) for state in values(first_instance.node_state))
    @test any(haskey(state.constraints, :balance_constraint) for state in values(first_instance.node_state))
end

@testset "Problem Architecture" begin
    test_problem_architecture()
end

end # module TestProblemArchitecture
