function generate_operation_subproblem(
    instance::ProblemInstance,
    case_settings::NamedTuple,
    include_subproblem_slacks::Bool,
)

    model = create_named_problem_model(instance)

    @variable(model, vREF == 1)

    model[:eVariableCost] = AffExpr(0.0)
    
    add_linking_variables!(instance, model; sync=true)

    linking_variable_refs = setdiff(all_variables(model), model[:vREF])
    register_linking_variable_updates!(instance, linking_variable_refs)
    linking_variables = name.(linking_variable_refs)

    define_available_capacity!(instance, model; sync=true)

    operation_model!(instance, model; sync=true)

    if include_subproblem_slacks == true
        @info("Adding slack variables to ensure subproblems are always feasible")
        slack_penalty = 2*maximum(coefficient(model[:eVariableCost],v) for v in all_variables(model))
        eq_cons_to_be_relaxed =  get_all_balance_constraints(instance);
        less_ineq_cons_to_be_relaxed = get_all_policy_constraints(instance);
        greater_ineq_cons_to_be_relaxed = Vector{ConstraintRef}();
        add_slack_variables!(model,slack_penalty,eq_cons_to_be_relaxed,less_ineq_cons_to_be_relaxed,greater_ineq_cons_to_be_relaxed)
    end
    
    period_index = get_primary_time_data(instance.static_system).period_index

    period_lengths = collect(case_settings.PeriodLengths)

    discount_rate = case_settings.DiscountRate

    discount_factor = present_value_factor(discount_rate, period_lengths)
    
    opexmult = present_value_annuity_factor.(discount_rate, period_lengths)

    @objective(model, Min, discount_factor[period_index] * opexmult[period_index] * model[:eVariableCost])

    return model, linking_variables


end

function register_linking_variable_updates!(instance::ProblemInstance, linking_variable_refs)
    clear_updates!(instance.update_map; kind=:fix)
    seen_keys = Set{String}()

    for (component_type, state_dict) in (
        (:node, instance.node_state),
        (:transformation, instance.transformation_state),
        (:storage, instance.storage_state),
        (:long_duration_storage, instance.long_duration_storage_state),
        (:unidirectional_edge, instance.unidirectional_edge_state),
        (:bidirectional_edge, instance.bidirectional_edge_state),
        (:unit_commitment_edge, instance.unit_commitment_edge_state),
    )
        for state in values(state_dict)
            register_local_state_linking_updates!(
                instance.update_map,
                component_type,
                state,
                linking_variable_refs;
                seen_keys,
            )
        end
    end

    return instance.update_map
end

function register_local_state_linking_updates!(
    update_map::UpdateMap,
    component_type::Symbol,
    state::AbstractLocalState,
    linking_variable_refs;
    seen_keys::Set{String}=Set{String}(),
)
    for (field, payload) in pairs(state.variables)
        register_field_linking_updates!(
            update_map,
            UpdateTarget(
                component_type = component_type,
                component_index = state.global_index,
                field = field,
            ),
            payload,
            linking_variable_refs;
            seen_keys,
        )
    end

    return update_map
end

function register_field_linking_updates!(
    update_map::UpdateMap,
    target::UpdateTarget,
    value::VariableRef,
    linking_variable_refs;
    seen_keys::Set{String}=Set{String}(),
)
    if value in linking_variable_refs
        source_key = name(value)
        if !isempty(source_key) && !(source_key in seen_keys)
            push!(seen_keys, source_key)
            register_fix_update!(
                update_map;
                component_type = target.component_type,
                component_index = target.component_index,
                field = target.field,
                ref = value,
                source_key = source_key,
            )
        end
    end
    return update_map
end

function register_field_linking_updates!(
    update_map::UpdateMap,
    target::UpdateTarget,
    value::AbstractArray,
    linking_variable_refs;
    seen_keys::Set{String}=Set{String}(),
)
    for item in value
        register_field_linking_updates!(update_map, target, item, linking_variable_refs; seen_keys)
    end
    return update_map
end

function register_field_linking_updates!(
    update_map::UpdateMap,
    target::UpdateTarget,
    value::JuMP.Containers.DenseAxisArray,
    linking_variable_refs;
    seen_keys::Set{String}=Set{String}(),
)
    for item in value
        register_field_linking_updates!(update_map, target, item, linking_variable_refs; seen_keys)
    end
    return update_map
end

function register_field_linking_updates!(
    update_map::UpdateMap,
    target::UpdateTarget,
    value::AbstractDict,
    linking_variable_refs;
    seen_keys::Set{String}=Set{String}(),
)
    for item in values(value)
        register_field_linking_updates!(update_map, target, item, linking_variable_refs; seen_keys)
    end
    return update_map
end

function register_field_linking_updates!(
    update_map::UpdateMap,
    target::UpdateTarget,
    value,
    linking_variable_refs;
    seen_keys::Set{String}=Set{String}(),
)
    return update_map
end

function initialize_subproblem(problem_bundle::NamedTuple,optimizer::Optimizer,case_settings::NamedTuple,include_subproblem_slacks::Bool)
    
    subproblem,linking_variables_sub = generate_operation_subproblem(problem_bundle.instance,case_settings,include_subproblem_slacks);

    set_optimizer(subproblem, optimizer)

    set_silent(subproblem)

    if problem_bundle.instance.static_system.settings.ConstraintScaling
        @info "Scaling constraints and RHS"
        scale_constraints!(subproblem)
    end

    return subproblem,linking_variables_sub
end

function initialize_local_subproblems!(problem_bundles_local::Vector,subproblems_local::Vector{Dict{Any,Any}},local_indices::UnitRange{Int64},optimizer::Optimizer,case_settings::NamedTuple, include_subproblem_slacks)

    nW = length(problem_bundles_local)

    for i=1:nW
		subproblem,linking_variables_sub = initialize_subproblem(problem_bundles_local[i],optimizer,case_settings,include_subproblem_slacks::Bool);
        subproblems_local[i][:model] = subproblem;
        subproblems_local[i][:linking_variables_sub] = linking_variables_sub;
        subproblems_local[i][:subproblem_index] = local_indices[i];
        subproblems_local[i][:problem_instance] = problem_bundles_local[i].instance
    end
end

function initialize_subproblems!(problem_bundles::Vector,opt::Dict,case_settings::NamedTuple,distributed_bool::Bool,include_subproblem_slacks::Bool)
    
    if distributed_bool
        subproblems, linking_variables_sub = initialize_dist_subproblems!(problem_bundles,opt,case_settings,include_subproblem_slacks)
    else
        subproblems, linking_variables_sub = initialize_serial_subproblems!(problem_bundles,opt,case_settings,include_subproblem_slacks)
    end

    return subproblems, linking_variables_sub
end

function initialize_dist_subproblems!(problem_bundles::Vector,opt::Dict,case_settings::NamedTuple,include_subproblem_slacks::Bool)

    ##### Initialize a distributed arrays of JuMP models
	## Start pre-solve timer
     
	subproblem_generation_time = time()

    subproblems_all = distribute([Dict() for i in 1:length(problem_bundles)]);

    @sync for p in workers()
        @async @spawnat p begin
            W_local = localindices(subproblems_all)[1];
            problem_bundles_local = [problem_bundles[k] for k in W_local];
            optimizer = create_optimizer(opt[:solver], opt_env(opt[:solver]), opt[:attributes])
            initialize_local_subproblems!(problem_bundles_local,localpart(subproblems_all),W_local,optimizer,case_settings,include_subproblem_slacks);
        end
    end

	p_id = workers();
    np_id = length(p_id);

    linking_variables_sub = [Dict() for k in 1:np_id];

    @sync for k in 1:np_id
        @async linking_variables_sub[k]= @fetchfrom p_id[k] get_local_linking_variables(localpart(subproblems_all))
    end

	linking_variables_sub = merge(linking_variables_sub...);

    ## Record pre-solver time
	subproblem_generation_time = time() - subproblem_generation_time
	@info("Distributed operational subproblems generation took $(round(subproblem_generation_time, digits=3)) seconds")

    return subproblems_all,linking_variables_sub

end

function initialize_serial_subproblems!(problem_bundles::Vector,opt::Dict,case_settings::NamedTuple,include_subproblem_slacks::Bool)

    ##### Initialize a array of JuMP models
	## Start pre-solve timer

    optimizer = create_optimizer(opt[:solver], opt_env(opt[:solver]), opt[:attributes])

	subproblem_generation_time = time()

    subproblems_all = [Dict() for i in 1:length(problem_bundles)];

    initialize_local_subproblems!(problem_bundles,subproblems_all, 1:length(problem_bundles),optimizer,case_settings,include_subproblem_slacks);

    linking_variables_sub = [get_local_linking_variables([subproblems_all[k]]) for k in 1:length(problem_bundles)];
    linking_variables_sub = merge(linking_variables_sub...);

    ## Record pre-solver time
	subproblem_generation_time = time() - subproblem_generation_time
	@info("Serial subproblems generation took $subproblem_generation_time seconds")

    return subproblems_all,linking_variables_sub

end

function get_local_linking_variables(subproblems_local::Vector{Dict{Any,Any}})

    local_variables=Dict();

    for sp in subproblems_local
		w = sp[:subproblem_index];
        local_variables[w] = sp[:linking_variables_sub]
    end

    return local_variables


end

function add_slack_variables!(model::Model,
                            slack_penalty::Float64, 
                            eq_cons::Vector,
                            less_ineq_cons::Vector,
                            greater_ineq_cons::Vector)

    @variable(model, myslack_max >= 0)

    if !isempty(less_ineq_cons)
        for c in less_ineq_cons
            set_normalized_coefficient(c, myslack_max, -1)
        end
    end

    if !isempty(greater_ineq_cons)
        for c in greater_ineq_cons
            set_normalized_coefficient(c, myslack_max, 1)
        end
    end

    if !isempty(eq_cons)
        n = length(eq_cons)
        @variable(model, myslack_eq[1:n])
        for i in 1:n
            set_normalized_coefficient(eq_cons[i], myslack_eq[i], -1)
        end
        @constraint(model, [i in 1:n], myslack_eq[i] <= myslack_max)
        @constraint(model, [i in 1:n], -myslack_eq[i] <= myslack_max)
    end

    model[:eVariableCost] += slack_penalty * myslack_max

    return nothing
end

function compute_slack_penalty_value(system::System)
    x = 0.0;
    for n in system.locations
        if isa(n,Node) && !isempty(non_served_demand(n))
            w = subperiod_indices(n)[1]
            y = subperiod_weight(n, w) * maximum(price_non_served_demand(n,s) for s in segments_non_served_demand(n))
            if y>x
                x = y
            end
        end
    end 

    
    if x==0.0
        penalty = 1e3;
    else
        penalty = 2*x
    end

    @info ("Slack penalty value: $penalty")

    return penalty

end

function get_all_balance_constraints(system::System)
    balance_constraints = Vector{JuMPConstraint}();
    for n in system.locations
        ### Add slacks also when non-served demand is modeled to cover cases where supply is greater than demand
        if isa(n,Node) #### && isempty(non_served_demand(n)) 
            for c in n.constraints
                if isa(c, BalanceConstraint)
                        for i in keys(n.balance_data)
                            for t in time_interval(n)
                                push!(balance_constraints, c.constraint_ref[i][t])
                            end
                        end
                    end
            end
        end
    end 

    for a in system.assets
        for t in fieldnames(typeof(a))
            g = getfield(a,t);
            if isa(g,LongDurationStorage)
                for c in g.constraints
                    if isa(c, BalanceConstraint)
                        STARTS = [first(sp) for sp in subperiods(g)];
                        for i in keys(g.balance_data)
                            for t in STARTS
                                push!(balance_constraints, c.constraint_ref[i][t])
                            end
                        end
                    end
                    if isa(c, LongDurationStorageChangeConstraint)
                        for w in subperiod_indices(g)
                            push!(balance_constraints, c.constraint_ref[w])
                        end
                    end
                end
            end
        end
    end
    return balance_constraints
end

function get_all_balance_constraints(instance::ProblemInstance)
    balance_constraints = JuMPConstraint[]

    for (idx, node) in zip(instance.spec.node_indices, selected_nodes(instance))
        state = instance.node_state[idx]
        !haskey(state.constraints, :balance_constraint) && continue
        constraint = state.constraints[:balance_constraint]
        for balance_id in keys(node.balance_data)
            for t in state.local_time_indices
                push!(balance_constraints, constraint.constraint_ref[balance_id][t])
            end
        end
    end

    for (idx, storage) in zip(instance.spec.long_duration_storage_indices, selected_long_duration_storages(instance))
        state = instance.long_duration_storage_state[idx]

        if haskey(state.constraints, :balance_constraint)
            constraint = state.constraints[:balance_constraint]
            starts = [first(sp) for sp in subperiods(storage)]
            for balance_id in keys(storage.balance_data)
                for t in starts
                    push!(balance_constraints, constraint.constraint_ref[balance_id][t])
                end
            end
        end

        if haskey(state.constraints, :long_duration_storage_change_constraint)
            constraint = state.constraints[:long_duration_storage_change_constraint]
            for w in subperiod_indices(storage)
                push!(balance_constraints, constraint.constraint_ref[w])
            end
        end
    end

    return balance_constraints
end


function get_all_policy_constraints(system::System)
    policy_constraints = Vector{JuMPConstraint}();
    for n in system.locations
        if isa(n,Node) && isempty(n.price_unmet_policy)
            for c in n.constraints
                if isa(c, PolicyConstraint)
                    for w in subperiod_indices(n)
                        push!(policy_constraints, c.constraint_ref[w])
                    end
                end
            end
        end
    end 
    return policy_constraints
end

function get_all_policy_constraints(instance::ProblemInstance)
    policy_constraints = JuMPConstraint[]

    for (idx, node) in zip(instance.spec.node_indices, selected_nodes(instance))
        isempty(node.price_unmet_policy) || continue
        state = instance.node_state[idx]
        for constraint in get(state.constraints, :policy_constraints, PolicyConstraint[])
            for w in subperiod_indices(node)
                push!(policy_constraints, constraint.constraint_ref[w])
            end
        end
    end

    return policy_constraints
end

function update_with_subproblem_solutions!(subproblems::Union{Vector{Dict{Any, Any}},DistributedArrays.DArray}, results::NamedTuple)
    if isa(subproblems, DistributedArrays.DArray)
        @sync for p in workers()
            @async @spawnat p begin
                update_local_subproblem_solutions!(localpart(subproblems), results.planning_sol)
            end
        end
    else
        update_local_subproblem_solutions!(subproblems, results.planning_sol)
    end
    return nothing
end

function update_local_subproblem_solutions!(
    subproblems_local::Vector{Dict{Any,Any}},
    planning_sol::NamedTuple,
)
    for subproblem in subproblems_local
        update_subproblem_solution!(subproblem, planning_sol)
    end
    return nothing
end

function update_subproblem_solution!(subproblem::Dict{Any,Any}, planning_sol::NamedTuple)
    instance = get(subproblem, :problem_instance, nothing)
    if !isnothing(instance) && !isempty(fix_update_instructions(instance.update_map))
        apply_planning_solution!(instance, planning_sol.values)
        optimize!(subproblem[:model])
        if !has_values(subproblem[:model])
            compute_conflict!(subproblem[:model])
            error("Final subproblem resolve failed after applying in-place updates.")
        end
        capture_problem_solution_values!(instance)
    else
        MacroEnergySolvers.solve_subproblem(
            subproblem[:model],
            planning_sol,
            subproblem[:linking_variables_sub],
            true,
        )
        if !isnothing(instance) && has_values(subproblem[:model])
            capture_problem_solution_values!(instance)
        end
    end
    return nothing
end
