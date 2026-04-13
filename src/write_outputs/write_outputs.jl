"""
Write results when using Monolithic as solution algorithm.
"""
function write_outputs(
    case_path::AbstractString, 
    case::Case, 
    model::Model
)
    num_periods = number_of_periods(case)
    periods = get_periods(case)
    settings = get_settings(case)
    for (period_idx, period) in enumerate(periods)
        @info("Writing results for period $period_idx")
        results_dir = mkpath_for_period(case_path, num_periods, period_idx)
        write_period_outputs(results_dir, period_idx, period, model, settings)
    end
    write_settings(case, joinpath(case_path, "settings.json"))
    return nothing
end

"""
Write results when using Myopic as solution algorithm.
"""
function write_outputs_myopic(
    output_path::AbstractString, 
    case::Case, 
    model::Model, 
    system::System, 
    period_idx::Int
)
    num_periods = number_of_periods(case)
    settings = get_settings(case)
    # Create results directory to store outputs for this period
    results_dir = mkpath_for_period(output_path, num_periods, period_idx)

    if settings.MyopicSettings[:WriteModelLP]
        @info(" -- Writing LP file for period $(period_idx)")
        write_to_file(model, joinpath(results_dir, "model_period_$(period_idx).lp"))
    end

    write_period_outputs(results_dir, period_idx, system, model, settings)
    return nothing
end

"""
Write results when using Benders as solution algorithm.
"""
function write_outputs(case_path::AbstractString, case::Case, bd_results::BendersResults)

    settings = get_settings(case);
    num_periods = number_of_periods(case);
    periods = get_periods(case);

    period_to_subproblem_map, _ = get_period_to_subproblem_mapping(periods)

    # Collect subproblem data (flows, NSD, storage levels, operational costs)
    @info "Collecting subproblem results..."
    subproblems_data = collect_data_from_subproblems(case, bd_results)
    
    # Extract individual result types from the unified extraction
    flow_df = flows(subproblems_data)
    nsd_df = non_served_demand(subproblems_data)
    storage_level_df = storage_levels(subproblems_data)
    curtailment_df = curtailment(subproblems_data)
    operational_costs_df = operational_costs(subproblems_data)
    
    # get the policy slack variables from the operational subproblems
    slack_vars = collect_distributed_policy_slack_vars(bd_results)

    # get the constraint duals from the operational subproblems
    # for now, only balance constraints are exported
    balance_duals = collect_distributed_constraint_duals(bd_results, BalanceConstraint)

    for (period_idx, period) in enumerate(periods)
        @info("Writing results for period $period_idx")

        ## Create results directory to store the results
        results_dir = mkpath_for_period(case_path, num_periods, period_idx)

        planning_output_instance = if length(bd_results.planning_instances) >= period_idx
            bd_results.planning_instances[period_idx]
        else
            nothing
        end
        planning_output_system = isnothing(planning_output_instance) ? period : planning_output_instance.static_system

        # subproblem indices for the current period
        subop_indices_period = period_to_subproblem_map[period_idx]

        # Capacity and planning-metadata outputs prefer the planning-period ProblemInstance when available.
        if isnothing(planning_output_instance)
            write_capacity(joinpath(results_dir, "capacity.csv"), planning_output_system)
        else
            write_capacity(joinpath(results_dir, "capacity.csv"), planning_output_instance)
        end

        # Flow results
        write_flows(joinpath(results_dir, "flows.csv"), planning_output_system, flow_df[subop_indices_period])

        # Non-served demand results
        write_non_served_demand(joinpath(results_dir, "non_served_demand.csv"), planning_output_system, nsd_df[subop_indices_period])

        # Storage level results
        write_storage_level(joinpath(results_dir, "storage_level.csv"), planning_output_system, storage_level_df[subop_indices_period])
        
        # Curtailment results
        write_curtailment(joinpath(results_dir, "curtailment.csv"), planning_output_system, curtailment_df[subop_indices_period])

        # Sub-period weights (for downstream revenue and weighted-sum calculations)
        if isnothing(planning_output_instance)
            write_time_weights(joinpath(results_dir, "time_weights.csv"), planning_output_system)
        else
            write_time_weights(joinpath(results_dir, "time_weights.csv"), planning_output_instance)
        end

        # Cost results (system level)
        cost_output_problem = isnothing(planning_output_instance) ? planning_output_system : planning_output_instance
        costs = prepare_costs_benders(cost_output_problem, bd_results, subop_indices_period, settings)

        write_costs(joinpath(results_dir, "costs.csv"), cost_output_problem, costs)
        
        write_undiscounted_costs(joinpath(results_dir, "undiscounted_costs.csv"), cost_output_problem, costs)
        
        # Detailed cost breakdown (assets and zones level)
        write_detailed_costs_benders(results_dir, cost_output_problem, costs, operational_costs_df[subop_indices_period], settings)

        # Write dual values (if enabled)
        # Scaling factor to account for discounting duals in multi-period models
        var_cost_discount = compute_variable_cost_discount_scaling(period_idx, settings)
        if planning_output_system.settings.DualExportsEnabled
            period_slack_vars = get(slack_vars, period_idx, Dict())
            period_balance_duals = get(balance_duals, period_idx, Dict())

            write_balance_duals(results_dir, planning_output_system, period_balance_duals, var_cost_discount)
            write_co2_cap_duals(results_dir, planning_output_system, period_slack_vars, var_cost_discount)
        end

        # Full time series reconstruction (if enabled and TDR is used)
        if settings.WriteFullTimeseries
            write_full_timeseries(results_dir, planning_output_system,
                flow_df[subop_indices_period], 
                nsd_df[subop_indices_period],
                storage_level_df[subop_indices_period], 
                curtailment_df[subop_indices_period];
                var_cost_discount,
                balance_duals=get(balance_duals, period_idx, Dict()))
        end
    end
    	
    write_benders_convergence(case_path, bd_results)

    write_settings(case, joinpath(case_path, "settings.json"))
    return nothing
end

"""
    write_period_outputs(results_dir, period_idx, system, model, settings)

Write all outputs for a single period (one iteration of the Monolithic/Myopic loop).
Sets up cost expressions, then writes capacity, costs, flows, NSD, storage, and duals.
Used by Monolithic in its loop and by Myopic after setup.
"""
function write_period_outputs(
    results_dir::AbstractString,
    period_idx::Int,
    system::System,
    model::Model,
    settings::NamedTuple
)
    
    # Capacity results
    write_capacity(joinpath(results_dir, "capacity.csv"), system)
    
    # Cost results (system level)
    create_discounted_cost_expressions!(model, system, settings)
    compute_undiscounted_costs!(model, system, settings)
    write_costs(joinpath(results_dir, "costs.csv"), system, model)
    write_undiscounted_costs(joinpath(results_dir, "undiscounted_costs.csv"), system, model)
    # Cost results (detailed breakdown by type and zone, discounted and undiscounted)
    write_detailed_costs(results_dir, system, model, settings)

    # Flow results
    write_flow(joinpath(results_dir, "flows.csv"), system)
    # Non-served demand results
    write_non_served_demand(joinpath(results_dir, "non_served_demand.csv"), system)
    # Storage level results
    write_storage_level(joinpath(results_dir, "storage_level.csv"), system)
    # Curtailment results
    write_curtailment(joinpath(results_dir, "curtailment.csv"), system)

    # Sub-period weights (for downstream revenue and weighted-sum calculations)
    write_time_weights(joinpath(results_dir, "time_weights.csv"), system)

    # Write dual values (if enabled)
    # Scaling factor to account for discounting duals in multi-period models
    var_cost_discount = compute_variable_cost_discount_scaling(period_idx, settings)
    if system.settings.DualExportsEnabled
        ensure_duals_available!(model)
        write_duals(results_dir, system, var_cost_discount)
    end

    # Full time series reconstruction (if enabled and TDR is used)
    if settings.WriteFullTimeseries
        write_full_timeseries(results_dir, system; var_cost_discount)
    end

    return nothing
end
