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
"""
Convert DenseAxisArray to Dict, preserving axis information.
"""
function densearray_to_dict(arr::JuMP.Containers.DenseAxisArray)
    ndims = length(arr.axes)
    
    if ndims == 1
        return Dict(idx => JuMP.value(arr[idx]) for idx in arr.axes[1])
    elseif ndims == 2
        return Dict((i, j) => JuMP.value(arr[i, j]) for i in arr.axes[1], j in arr.axes[2])
    else
        return Dict(idx_tuple => JuMP.value(arr[idx_tuple...]) 
            for idx_tuple in Iterators.product(arr.axes...))
    end
end

"""
Convert Dict back to DenseAxisArray.
"""
function dict_to_densearray(dict::Dict)
    first_key = first(keys(dict))
    
    if first_key isa Tuple
        ndims = length(first_key)
        
        # Extract unique values for each dimension from the dictionary keys
        # This will make sure to map the dictionary keys to the DenseAxisArray indices
        key_list = collect(keys(dict))
        all_axes = []
        for dim in 1:ndims
            axis_vals = sort(unique([k[dim] for k in key_list]))
            push!(all_axes, axis_vals)
        end
        
        # Create data array from the dictionary values
        data = [get(dict, idx_tuple, NaN) for idx_tuple in Iterators.product(all_axes...)]
        
        return JuMP.Containers.DenseAxisArray(data, all_axes...)
    elseif isa(first_key, Int64)
        # Fallback to 1D case if keys are not tuples
        indices = sort(collect(keys(dict)))
        values = [dict[i] for i in indices]
        return JuMP.Containers.DenseAxisArray(values, indices)
    else
        error("Unsupported key type: $(typeof(first_key))")
    end
end

function prepare_duals_benders!(period::System, slack_vars::Dict{Tuple{Symbol,Symbol}, Dict})
    for (node_id, slack_vars_key) in keys(slack_vars)
        node = find_node(period, node_id)
        @assert !isnothing(node)
        # Convert dict back to DenseAxisArray before assigning to the node
        # This will make sure the slack variables are stored in the correct format
        node.policy_slack_vars[slack_vars_key] = dict_to_densearray(slack_vars[(node_id, slack_vars_key)])
    end
    return nothing
end

function collect_distributed_policy_slack_vars(bd_results::BendersResults)
    p_id = workers()
    np_id = length(p_id)
    slack_vars = Vector{Dict{Int64, Dict{Tuple{Symbol,Symbol}, Dict}}}(undef, np_id)
    @sync for i in 1:np_id
        @async slack_vars[i] = @fetchfrom p_id[i] get_local_slack_vars(DistributedArrays.localpart(bd_results.op_subproblem))
    end
    
    # Merge dictionaries by period_index
    # Structure: period_index => (node_id, slack_vars_key) => {axis_idx => value}
    merged_slack_vars = Dict{Int64, Dict{Tuple{Symbol,Symbol}, Dict}}()
    for worker_dict in slack_vars
        for (period_idx, period_dict) in worker_dict
            if !haskey(merged_slack_vars, period_idx)
                merged_slack_vars[period_idx] = Dict{Tuple{Symbol,Symbol}, Dict}()
            end
            # Merge inner dictionaries for this period
            for (key, axis_dict) in period_dict
                if haskey(merged_slack_vars[period_idx], key)
                    # If same (node_id, slack_vars_key) exists, merge the axis dictionaries
                    merge!(merged_slack_vars[period_idx][key], axis_dict)
                else
                    merged_slack_vars[period_idx][key] = copy(axis_dict)
                end
            end
        end
    end
    
    return merged_slack_vars
end

function get_local_slack_vars(subproblems_local::Vector{Dict{Any,Any}})
    slack_vars = Dict{Int64, Dict{Tuple{Symbol, Symbol}, Dict}}()
    for i in eachindex(subproblems_local)
        system = subproblems_local[i][:system_local]
        for node in filter(n -> n isa Node, system.locations)
            period_index = system.time_data[:Electricity].period_index
            for slack_vars_key in keys(policy_slack_vars(node))
                # Create tuple key with (node_id, slack_vars_key) to keep track of the metadata
                key = (node.id, slack_vars_key)
                
                # Convert DenseAxisArray to Dict before assigning to the period_dict
                slack_array = policy_slack_vars(node)[slack_vars_key]
                axis_dict = densearray_to_dict(slack_array)
                
                # Ensure period_index dict exists
                period_dict = get!(slack_vars, period_index, Dict{Tuple{Symbol, Symbol}, Dict}())
                
                # Merge axis dictionaries (different subproblems have different time indices)
                if haskey(period_dict, key)
                    merge!(period_dict[key], axis_dict)
                else
                    period_dict[key] = axis_dict
                end
            end
        end
    end
    return slack_vars
end
