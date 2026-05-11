function add_period_to_planning_model!(
    problem::Problem,
    static_system::StaticSystem,
    system::System,
    next_system::Union{System,Nothing},
    next_static_system::Union{StaticSystem,Nothing},
    fixed_cost::Dict,
    investment_cost::Dict,
    om_fixed_cost::Dict,
)
    build_period_planning!(problem, static_system, system, next_system, next_static_system)

    add_feasibility_constraints!(static_system, problem)

    store_and_unregister_costs!(model(problem), system, fixed_cost, investment_cost, om_fixed_cost)
    return nothing
end

function finalize_planning_model_objective!(
    problem::Problem,
    periods::Vector{System},
    settings::NamedTuple,
    fixed_cost::Dict,
    investment_cost::Dict,
    om_fixed_cost::Dict,
)
    jump_model = model(problem)
    jump_model[:eAvailableCapacity] = available_capacity_refs(problem)

    period_indices = sort([period_index(system) for system in periods])
    period_lengths = collect(settings.PeriodLengths)
    discount_rate = settings.DiscountRate
    discount_factor = present_value_factor(discount_rate, period_lengths)

    @expression(jump_model, eFixedCostByPeriod[s in period_indices], discount_factor[s] * fixed_cost[s])
    @expression(jump_model, eFixedCost, sum(eFixedCostByPeriod[s] for s in period_indices))

    @expression(jump_model, eInvestmentFixedCostByPeriod[s in period_indices], discount_factor[s] * investment_cost[s])
    @expression(jump_model, eOMFixedCostByPeriod[s in period_indices], discount_factor[s] * om_fixed_cost[s])

    _, number_of_subperiods = get_period_to_subproblem_mapping(periods)
    @expression(jump_model, eLowerBoundOperatingCost[w in 1:number_of_subperiods], AffExpr(0.0))

    @objective(jump_model, Min, jump_model[:eFixedCost])

    return nothing
end

function available_capacity_refs(problem::Problem)
    available_capacity = Dict{BendersLinkKey,Any}()
    for component_field in CAPACITY_COMPONENT_FIELDS
        refs_by_key = getproperty(problem.refs, component_field)
        for (key, refs) in refs_by_key
            capacity_ref = capacity(capacity_refs(refs))
            if !isnothing(capacity_ref)
                available_capacity[BendersLinkKey(component_key=key, field=:capacity)] = capacity_ref
            end
        end
    end
    return available_capacity
end

function benders_link_variables(problem::Problem)
    links = Dict{BendersLinkKey,VariableRef}()

    for (key, refs) in problem.refs.nodes
        for (name, vars) in refs.policy_budgeting_vars
            for idx in keys(vars)
                links[BendersLinkKey(component_key=key, field=:policy_budgeting_vars, index=(name, idx))] = vars[idx]
            end
        end
    end

    for component_field in CAPACITY_COMPONENT_FIELDS
        for (key, refs) in getproperty(problem.refs, component_field)
            capacity_ref = capacity(capacity_refs(refs))
            capacity_ref isa VariableRef &&
                (links[BendersLinkKey(component_key=key, field=:capacity)] = capacity_ref)
        end
    end

    for (key, refs) in problem.refs.long_duration_storages
        if !isnothing(refs.storage_initial)
            for idx in keys(refs.storage_initial)
                links[BendersLinkKey(component_key=key, field=:storage_initial, index=(idx,))] = refs.storage_initial[idx]
            end
        end
        if !isnothing(refs.storage_change)
            for idx in keys(refs.storage_change)
                links[BendersLinkKey(component_key=key, field=:storage_change, index=(idx,))] = refs.storage_change[idx]
            end
        end
    end

    return links
end

function benders_planning_variables(problem::Problem)
    link_refs = benders_link_variables(problem)
    key_by_ref = Dict(ref => key for (key, ref) in link_refs)

    return [
        MacroEnergySolvers.BendersVariable(get(key_by_ref, variable, variable), variable)
        for variable in all_variables(model(problem))
    ]
end

function add_feasibility_constraints!(system::StaticSystem, problem::Problem)
    for g in system.long_duration_storages
        has_storage_max_level_constraint = any(isa.(g.constraints, MaxStorageLevelConstraint))
        has_storage_min_level_constraint = any(isa.(g.constraints, MinStorageLevelConstraint))
        has_init_storage_max_level_constraint = any(isa.(g.constraints, MaxInitStorageLevelConstraint))
        has_init_storage_min_level_constraint = any(isa.(g.constraints, MinInitStorageLevelConstraint))

        if has_storage_max_level_constraint && !has_init_storage_max_level_constraint
            @info("Adding max initial storage level constraint to storage $(id(g)) for feasibility")
            push!(g.constraints, MaxInitStorageLevelConstraint())
            Base.invokelatest(add_model_constraint!, g.constraints[end], g, problem)
        end

        if has_storage_min_level_constraint && !has_init_storage_min_level_constraint
            @info("Adding min initial storage level constraint to storage $(id(g)) for feasibility")
            push!(g.constraints, MinInitStorageLevelConstraint())
            Base.invokelatest(add_model_constraint!, g.constraints[end], g, problem)
        end
    end
    return nothing
end
