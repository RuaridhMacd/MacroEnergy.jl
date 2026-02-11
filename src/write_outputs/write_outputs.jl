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
    for (period_idx,period) in enumerate(periods)
        @info("Writing results for period $period_idx")
        
        create_discounted_cost_expressions!(model, period, get_settings(case))

        compute_undiscounted_costs!(model, period, get_settings(case))

        ## Create results directory to store the results
        if num_periods > 1
            # Create a directory for each period
            results_dir = joinpath(case_path, "results_period_$period_idx")
        else
            # Create a directory for the single period
            results_dir = joinpath(case_path, "results")
        end
        mkpath(results_dir)

        write_outputs(results_dir, period_idx, period, model, get_settings(case))
    end
    write_settings(case, joinpath(case_path, "settings.json"))
    return nothing
end

"""
Write results when using Myopic as solution algorithm. 
"""
function write_outputs(case_path::AbstractString, case::Case, myopic_results::MyopicResults)
    @debug("Outputs were already written during iteration.")
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

    # get the flow results from the operational subproblems
    flow_df = collect_flow_results(case, bd_results)

    # get the non-served demand results from the operational subproblems
    nsd_df = collect_non_served_demand_results(case, bd_results)

    # get the storage level results from the operational subproblems
    storage_level_df = collect_storage_level_results(case, bd_results)
    
    # get the policy slack variables from the operational subproblems
    slack_vars = collect_distributed_policy_slack_vars(bd_results)

    # get the constraint duals from the operational subproblems
    # for now, only balance constraints are exported
    balance_duals = collect_distributed_constraint_duals(bd_results, BalanceConstraint)

    for (period_idx, period) in enumerate(periods)
        @info("Writing results for period $period_idx")
        ## Create results directory to store the results
        if num_periods > 1
            # Create a directory for each period
            results_dir = joinpath(case_path, "results_period_$period_idx")
        else
            # Create a directory for the single period
            results_dir = joinpath(case_path, "results")
        end
        mkpath(results_dir)

        # subproblem indices for the current period
        subop_indices_period = period_to_subproblem_map[period_idx]

        # Note: period has been updated with the capacity values in planning_solution at the end of function solve_case
        # Capacity results
        write_capacity(joinpath(results_dir, "capacity.csv"), period)

        # Flow results
        write_flows(joinpath(results_dir, "flows.csv"), period, flow_df[subop_indices_period])

        # Non-served demand results
        write_non_served_demand(joinpath(results_dir, "non_served_demand.csv"), period, nsd_df[subop_indices_period])

        # Storage level results
        write_storage_level(joinpath(results_dir, "storage_level.csv"), period, storage_level_df[subop_indices_period])
        
        # Cost results
        costs = prepare_costs_benders(period, bd_results, subop_indices_period, settings)
        write_costs(joinpath(results_dir, "costs.csv"), period, costs)
        write_undiscounted_costs(joinpath(results_dir, "undiscounted_costs.csv"), period, costs)

        # Write dual values (if enabled)
        if period.settings.DualExportsEnabled
            # Move slack variables from subproblems to planning problem
            if haskey(slack_vars, period_idx)
                populate_slack_vars_from_subproblems!(period, slack_vars[period_idx])
            else
                @debug "No slack variables found for period $period_idx"
            end
            
            # Calculate and store constraint duals from subproblems to planning problem
            if haskey(balance_duals, period_idx)
                populate_constraint_duals_from_subproblems!(period, balance_duals[period_idx], BalanceConstraint)
            else
                @debug "No balance constraint duals found for period $period_idx"
            end
            
            # Scaling factor to account for discounting in multi-period models
            discount_scaling = compute_variable_cost_discount_scaling(period_idx, settings)
            write_duals_benders(results_dir, period, discount_scaling)
        end
    end
    write_settings(case, joinpath(case_path, "settings.json"))
    return nothing
end

"""
    Fallback function to write outputs for a single period.
"""
function write_outputs(
    results_dir::AbstractString, 
    period_idx::Int,
    system::System, 
    model::Model,
    settings::NamedTuple
)
    
    # Capacity results
    write_capacity(joinpath(results_dir, "capacity.csv"), system)
    
    # Cost results (system level)
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

    # Write dual values (if enabled)
    if system.settings.DualExportsEnabled
        ensure_duals_available!(model)
        # Scaling factor for variable cost portion of objective function
        discount_scaling = compute_variable_cost_discount_scaling(period_idx, settings)        
        write_duals(results_dir, system, discount_scaling)
    end

    return nothing
end