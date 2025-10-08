function prepare_costs_benders(system::System, 
    bd_results::BendersResults, 
    subop_indices::Vector{Int64}, 
    settings::NamedTuple
)
    planning_problem = bd_results.planning_problem
    subop_sol = bd_results.subop_sol
    planning_variable_values = bd_results.planning_sol.values

    create_discounted_cost_expressions!(planning_problem, system, settings)
    compute_undiscounted_costs!(planning_problem, system, settings)

    # Evaluate the fixed cost expressions in the planning problem. Note that this expression has been re-built
    # in compute_undiscounted_costs! to utilize undiscounted costs and the Benders planning solutions that are 
    # stored in system. So, no need to re-evaluate the expression on planning_variable_values.
    fixed_cost = value(planning_problem[:eFixedCost])
    # Evaluate the discounted fixed cost expression on the Benders planning solutions
    discounted_fixed_cost = value(x -> planning_variable_values[name(x)], planning_problem[:eDiscountedFixedCost])

    # evaluate the variable cost expressions using the subproblem solutions
    variable_cost = evaluate_vtheta_in_expression(planning_problem, :eVariableCost, subop_sol, subop_indices)
    discounted_variable_cost = evaluate_vtheta_in_expression(planning_problem, :eDiscountedVariableCost, subop_sol, subop_indices)

    return (
        eFixedCost = fixed_cost,
        eVariableCost = variable_cost,
        eDiscountedFixedCost = discounted_fixed_cost,
        eDiscountedVariableCost = discounted_variable_cost
    )
end
    
"""
Collect flow results from all subproblems, handling distributed case.
"""
function collect_flow_results(case::Case, bd_results::BendersResults)
    if case.settings.BendersSettings[:Distributed]
        return collect_distributed_flows(bd_results)
    else
        return collect_local_flows(bd_results)
    end
end

"""
Collect flow results from subproblems on distributed workers.
"""
function collect_distributed_flows(bd_results::BendersResults)
    p_id = workers()
    np_id = length(p_id)
    flow_df = Vector{Vector{DataFrame}}(undef, np_id)
    @sync for i in 1:np_id
        @async flow_df[i] = @fetchfrom p_id[i] get_local_expressions(get_optimal_flow, DistributedArrays.localpart(bd_results.op_subproblem))
    end
    return reduce(vcat, flow_df)
end

"""
Collect flow results from local subproblems.
"""
function collect_local_flows(bd_results::BendersResults)
    flow_df = Vector{DataFrame}(undef, length(bd_results.op_subproblem))
    for i in eachindex(bd_results.op_subproblem)
        system = bd_results.op_subproblem[i][:system_local]
        flow_df[i] = get_optimal_flow(system)
    end
    return flow_df
end