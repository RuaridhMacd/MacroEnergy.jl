function generate_model(case::Case, opt::Optimizer, ::Monolithic)
    @info("*** Generating monolithic model ***")

    if case.systems[1].settings.EnableJuMPDirectModel
        model = create_direct_model_with_optimizer(opt)
    else
        model = Model()
        set_optimizer(model, opt)
    end

    set_string_names_on_creation(model, case.systems[1].settings.EnableJuMPStringNames)

    @info("Generating model")
    start_time = time()

    @variable(model, vREF == 1)

    periods = get_periods(case)
    static_systems = StaticSystem.(periods)
    problem = Problem(static_systems; id=:monolithic, model)
    settings = get_settings(case)
    fixed_cost, investment_cost, om_fixed_cost, variable_cost = Dict(), Dict(), Dict(), Dict()

    for (period_idx, (system, static_system)) in enumerate(zip(periods, static_systems))
        next = period_idx < length(periods) ? periods[period_idx+1] : nothing
        next_static_system = period_idx < length(static_systems) ? static_systems[period_idx+1] : nothing
        add_period_to_model!(
            problem,
            static_system,
            system,
            next,
            next_static_system,
            fixed_cost,
            investment_cost,
            om_fixed_cost,
            variable_cost,
        )
    end

    finalize_model_objective!(model, settings, fixed_cost, investment_cost, om_fixed_cost, variable_cost)

    if case.systems[1].settings.ConstraintScaling
        @info "Scaling constraints and RHS"
        scale_constraints!(model)
    end
    
    @info(" -- Model generation complete, it took $(time() - start_time) seconds")
    
    return problem
end

function generate_model(system::System, opt::Optimizer, settings::NamedTuple, ::Monolithic)
    @info("*** Generating monolithic model for period $(period_index(system)) ***")

    if system.settings.EnableJuMPDirectModel
        model = create_direct_model_with_optimizer(opt)
    else
        model = Model()
        set_optimizer(model, opt)
    end

    set_string_names_on_creation(model, system.settings.EnableJuMPStringNames)

    @variable(model, vREF == 1)

    fixed_cost, investment_cost, om_fixed_cost, variable_cost = Dict(), Dict(), Dict(), Dict()

    static_system = StaticSystem(system)
    problem = Problem(static_system; id=Symbol(:period_, period_index(system)), model)
    add_period_to_model!(problem, static_system, system, nothing, nothing, fixed_cost, investment_cost, om_fixed_cost, variable_cost)

    finalize_model_objective!(model, settings, fixed_cost, investment_cost, om_fixed_cost, variable_cost)

    if system.settings.ConstraintScaling
        @info "Scaling constraints and RHS"
        scale_constraints!(model)
    end

    return problem

end

function generate_model(case::Case, opt::Dict{Symbol,Dict{Symbol,Any}}, ::Benders)
    @info("*** Generating Benders decomposition model ***")
    
    planning_optimizer = opt[:planning]
    optimizer = create_optimizer(planning_optimizer[:solver], opt_env(planning_optimizer[:solver]), planning_optimizer[:attributes])
    planning_model = Model()
    set_optimizer(planning_model, optimizer)
    set_string_names_on_creation(planning_model, case.systems[1].settings.EnableJuMPStringNames)
    set_silent(planning_model)
    
    @info("Generating planning problem")
    start_time = time()
    
    @variable(planning_model, vREF == 1)
    
    periods = get_periods(case)
    static_systems = StaticSystem.(periods)
    subproblem_specs = temporal_benders_problem_specs(static_systems)
    sliced_subproblem_systems = [slice_system(static_systems, spec) for spec in subproblem_specs]
    planning_problem = Problem(static_systems; id=:planning, model=planning_model)
    settings = get_settings(case)
    fixed_cost, investment_cost, om_fixed_cost = Dict(), Dict(), Dict()
    
    for (i, (system, static_system)) in enumerate(zip(periods, static_systems))
        next = i < length(periods) ? periods[i+1] : nothing
        next_static_system = i < length(static_systems) ? static_systems[i+1] : nothing
        add_period_to_planning_model!(
            planning_problem,
            static_system,
            system,
            next,
            next_static_system,
            fixed_cost,
            investment_cost,
            om_fixed_cost,
        )
    end
    
    finalize_planning_model_objective!(planning_problem, periods, settings, fixed_cost, investment_cost, om_fixed_cost, length(subproblem_specs))
    planning_variables = benders_planning_variables(planning_problem)
    
    @info(" -- Planning problem generation complete, it took $(time() - start_time) seconds")
    
    if case.systems[1].settings.ConstraintScaling
        @info "Scaling constraints and RHS"
        scale_constraints!(planning_model)
    end
    
    bd_setup = settings.BendersSettings
    subproblems, linking_variables_sub = generate_subproblems(
        sliced_subproblem_systems, subproblem_specs, opt[:subproblems], settings,
        bd_setup[:Distributed], bd_setup[:IncludeSubproblemSlacksAutomatically]
    )
    period_to_subproblem_map, _ = get_period_to_subproblem_mapping(subproblem_specs)

    return BendersProblem(
        settings=bd_setup,
        planning=planning_problem,
        subproblems=subproblems,
        planning_variables=planning_variables,
        linking_variables_sub=linking_variables_sub,
        period_to_subproblem_map=period_to_subproblem_map,
    )
end

function generate_model(system::System, opt::Dict{Symbol,Dict{Symbol,Any}}, settings::NamedTuple, ::Benders)
    @info("*** Generating Benders decomposition model ***")
    
    planning_optimizer = opt[:planning]
    optimizer = create_optimizer(planning_optimizer[:solver], opt_env(planning_optimizer[:solver]), planning_optimizer[:attributes])
    model = Model()
    set_optimizer(model, optimizer)
    set_string_names_on_creation(model, system.settings.EnableJuMPStringNames)
    set_silent(model)
    
    @info("Generating planning problem for period $(period_index(system))")
    
    @variable(model, vREF == 1)
    
    fixed_cost, investment_cost, om_fixed_cost = Dict(), Dict(), Dict()
    
    static_system = StaticSystem(system)
    subproblem_specs = temporal_benders_problem_specs([static_system])
    sliced_subproblem_systems = [slice_system(static_system, spec) for spec in subproblem_specs]
    planning_problem = Problem(static_system; id=Symbol(:planning_period_, period_index(system)), model)

    add_period_to_planning_model!(
        planning_problem,
        static_system,
        system,
        nothing,
        nothing,
        fixed_cost,
        investment_cost,
        om_fixed_cost,
    )
    
    finalize_planning_model_objective!(planning_problem, [system], settings, fixed_cost, investment_cost, om_fixed_cost, length(subproblem_specs))
    planning_variables = benders_planning_variables(planning_problem)
    
    if system.settings.ConstraintScaling
        @info "Scaling constraints and RHS"
        scale_constraints!(model)
    end
    
    bd_setup = settings.BendersSettings
    subproblems, linking_variables_sub = generate_subproblems(
        sliced_subproblem_systems, subproblem_specs, opt[:subproblems], settings,
        bd_setup[:Distributed], bd_setup[:IncludeSubproblemSlacksAutomatically]
    )
    period_to_subproblem_map, _ = get_period_to_subproblem_mapping(subproblem_specs)

    return BendersProblem(
        settings=bd_setup,
        planning=planning_problem,
        subproblems=subproblems,
        planning_variables=planning_variables,
        linking_variables_sub=linking_variables_sub,
        period_to_subproblem_map=period_to_subproblem_map,
    )
end

function add_period_to_model!(
    problem::Problem,
    static_system::StaticSystem,
    system::System,
    next_system::Union{System, Nothing},
    next_static_system::Union{StaticSystem, Nothing},
    fixed_cost::Dict,
    investment_cost::Dict,
    om_fixed_cost::Dict,
    variable_cost::Dict
)
    model = problem.model

    model[:eVariableCost] = AffExpr(0.0)

    build_period_planning!(problem, static_system, system, next_system, next_static_system)

    @info(" -- Generating operational model")
    operation_model!(static_system, problem)

    store_and_unregister_costs!(model, system, fixed_cost, investment_cost, om_fixed_cost)

    variable_cost[period_index(system)] = model[:eVariableCost]
    unregister(model, :eVariableCost)

    return problem
end

function build_period_planning!(
    problem::Problem,
    static_system::StaticSystem,
    system::System,
    next_system::Union{System, Nothing},
    next_static_system::Union{StaticSystem, Nothing}
)
    @info(" -- Period $(period_index(system))")

    model = problem.model
    model[:eFixedCost] = AffExpr(0.0)
    model[:eInvestmentFixedCost] = AffExpr(0.0)
    model[:eOMFixedCost] = AffExpr(0.0)

    @info(" -- Adding linking variables")
    add_linking_variables!(static_system, problem)

    @info(" -- Defining available capacity")
    define_available_capacity!(static_system, problem)

    @info(" -- Generating planning model")
    planning_model!(static_system, problem)

    if system.settings.Retrofitting
        @info(" -- Adding retrofit constraints")
        add_retrofit_constraints!(system, model)
    end

    @info(" -- Including age-based retirements")
    add_age_based_retirements!(static_system, problem)

    if !isnothing(next_system)
        @info(" -- Available capacity in period $(period_index(system)) is being carried over to period $(period_index(next_system))")
        carry_over_capacities!(problem, next_static_system, static_system)
    end

    return nothing
end

"""Store fixed cost expressions in the cost dicts and unregister them from the model."""
function store_and_unregister_costs!(model::Model, system::System, fixed_cost::Dict, investment_cost::Dict, om_fixed_cost::Dict)
    curr_period = period_index(system)
    model[:eFixedCost] = model[:eInvestmentFixedCost] + model[:eOMFixedCost]
    fixed_cost[curr_period] = model[:eFixedCost]
    investment_cost[curr_period] = model[:eInvestmentFixedCost]
    om_fixed_cost[curr_period] = model[:eOMFixedCost]
    unregister(model, :eFixedCost)
    unregister(model, :eInvestmentFixedCost)
    unregister(model, :eOMFixedCost)
end

function finalize_model_objective!(
    model::Model,
    settings::NamedTuple,
    fixed_cost::Dict,
    investment_cost::Dict,
    om_fixed_cost::Dict,
    variable_cost::Dict
)
    period_indices = sort(collect(keys(fixed_cost)))
    period_lengths = collect(settings.PeriodLengths)
    discount_rate = settings.DiscountRate
    discount_factor = present_value_factor(discount_rate, period_lengths)

    @expression(model, eFixedCostByPeriod[s in period_indices], discount_factor[s] * fixed_cost[s])

    @expression(model, eInvestmentFixedCostByPeriod[s in period_indices], discount_factor[s] * investment_cost[s])

    @expression(model, eOMFixedCostByPeriod[s in period_indices], discount_factor[s] * om_fixed_cost[s])

    @expression(model, eFixedCost, sum(eFixedCostByPeriod[s] for s in period_indices))

    opexmult = present_value_annuity_factor.(discount_rate, period_lengths)

    @expression(model, eVariableCostByPeriod[s in period_indices], discount_factor[s] * opexmult[s] * variable_cost[s])

    @expression(model, eVariableCost, sum(eVariableCostByPeriod[s] for s in period_indices))

    @objective(model, Min, model[:eFixedCost] + model[:eVariableCost])

    return nothing
end

function foreach_problem_component!(f::F, system::StaticSystem, problem::Problem) where {F}
    for (component_field, spec_field) in PROBLEM_COMPONENT_FIELD_PAIRS
        refs_by_key = getproperty(problem.refs, component_field)

        for key in getproperty(problem.spec, spec_field)
            key.period_index == period_index(system) || continue
            f(component(system, key), refs_by_key[key])
        end
    end
    return nothing
end

function foreach_problem_component!(f::F, systems::AbstractVector{StaticSystem}, problem::Problem) where {F}
    for (component_field, spec_field) in PROBLEM_COMPONENT_FIELD_PAIRS
        refs_by_key = getproperty(problem.refs, component_field)

        for key in getproperty(problem.spec, spec_field)
            f(component(systems, key), refs_by_key[key])
        end
    end
    return nothing
end

constraint_refs(refs) = refs
constraint_refs(refs::UnidirectionalEdgeRefs) = refs.edge
constraint_refs(refs::BidirectionalEdgeRefs) = refs.edge

component_ref_field(::Node) = :nodes
component_ref_field(::Transformation) = :transformations
component_ref_field(::Storage) = :storages
component_ref_field(::LongDurationStorage) = :long_duration_storages
component_ref_field(::UnidirectionalEdge) = :unidirectional_edges
component_ref_field(::BidirectionalEdge) = :bidirectional_edges
component_ref_field(::EdgeWithUC) = :unit_commitment_edges

function constraint_model_and_refs(component, problem::AbstractProblem)
    refs = constraint_refs(get_component_refs(problem.refs, component))
    return model(problem), refs
end

function planning_model!(system::StaticSystem, problem::Problem)
    model = problem.model

    foreach_problem_component!(system, problem) do component, refs
        planning_model!(component, refs, model)
    end

    add_constraints_by_type!(system, problem, PlanningConstraint)
    return nothing
end


function operation_model!(system::StaticSystem, problem::Problem)
    foreach_problem_component!(system, problem) do component, refs
        operation_model!(component, refs, problem)
    end

    add_constraints_by_type!(system, problem, OperationConstraint)
    return nothing
end

function add_linking_variables!(system::StaticSystem, problem::Problem)
    model = problem.model

    foreach_problem_component!(system, problem) do component, refs
        add_linking_variables!(component, refs, model)
    end

    return nothing
end

function define_available_capacity!(system::StaticSystem, problem::Problem)
    model = problem.model

    foreach_problem_component!(system, problem) do component, refs
        define_available_capacity!(component, refs, model)
    end

    return nothing
end

function add_constraints_by_type!(
    system::StaticSystem,
    problem::Problem,
    constraint_type::DataType,
)
    foreach_problem_component!(system, problem) do component, refs
        add_constraints_by_type!(component, problem, constraint_type)
    end

    return nothing
end

function add_constraints_by_type!(
    y::Union{AbstractEdge,AbstractVertex},
    problem::AbstractProblem,
    constraint_type::DataType,
)
    for c in all_constraints(y)
        if isa(c, constraint_type)
            Base.invokelatest(add_model_constraint!, c, y, problem)
        end
    end
    return nothing
end

const CAPACITY_COMPONENT_FIELDS = (
    :storages,
    :long_duration_storages,
    :unidirectional_edges,
    :bidirectional_edges,
    :unit_commitment_edges,
)

function add_age_based_retirements!(system::StaticSystem, problem::Problem)
    for component_field in CAPACITY_COMPONENT_FIELDS
        for y in getproperty(system, component_field)
            if retirement_period(y) > 0 || min_retired_capacity_track(y) > 0.0
                push!(y.constraints, AgeBasedRetirementConstraint())
                Base.invokelatest(add_model_constraint!, y.constraints[end], y, problem)
            end
        end
    end
    return nothing
end

#### All new capacity built up to the retirement period must retire in the current period
### Key assumption: all capacity decisions are taken at the very beggining of the period.
### Example: Consider four periods of lengths [5,5,5,5] and technology with a lifetime of 15 years. 
### All capacity built in period 1 will have at most 10 years old at the start of period 3, so no age based retirement will be needed.
### In period 4 we will have to retire at least all new capacity built up until period get_retirement_period(4,15,[5,5,5,5])=1
function get_retirement_period(cur_period::Int,lifetime::Int,period_lengths::Vector{Int})

    return maximum(filter(r -> sum(period_lengths[t] for t in r:cur_period-1; init=0) >= lifetime,1:cur_period-1);init=0)

end

function compute_retirement_period!(system::System, period_lengths::Vector{Int})
    
    for a in system.assets
        compute_retirement_period!(a, period_lengths)
    end

    return nothing
end

function compute_retirement_period!(a::AbstractAsset, period_lengths::Vector{Int})

    for t in fieldnames(typeof(a))
        y = getfield(a, t)
        
        if :retirement_period ∈ Base.fieldnames(typeof(y))
            if can_retire(y)
                y.retirement_period = get_retirement_period(period_index(y),lifetime(y),period_lengths)
            end
        end
    end

    return nothing
end

function carry_over_capacities!(problem::Problem, system::StaticSystem, system_prev::StaticSystem)
    for component_field in CAPACITY_COMPONENT_FIELDS
        previous_components = getproperty(system_prev, component_field)
        previous_by_id = Dict(id(component) => component for component in previous_components)

        for y in getproperty(system, component_field)
            y_prev = get(previous_by_id, id(y), nothing)
            if isnothing(y_prev)
                validate_existing_capacity(y)
            else
                carry_over_capacities!(problem, y, y_prev)
            end
        end
    end
    return nothing
end

function carry_over_capacities!(
    problem::Problem,
    y::Union{AbstractEdge,AbstractStorage},
    y_prev::Union{AbstractEdge,AbstractStorage},
)
    has_capacity(y_prev) || return nothing

    refs = capacity_refs(get_component_refs(problem.refs, y))
    refs_prev = capacity_refs(get_component_refs(problem.refs, y_prev))

    refs.existing_capacity = capacity(refs_prev)

    for prev_period in keys(new_capacity_track(refs_prev))
        refs.new_capacity_track[prev_period] = new_capacity_track(refs_prev, prev_period)
        refs.retired_capacity_track[prev_period] = retired_capacity_track(refs_prev, prev_period)

        if y isa AbstractEdge
            refs.retrofitted_capacity_track[prev_period] = retrofitted_capacity_track(refs_prev, prev_period)
        end
    end

    return nothing
end

function compute_annualized_costs!(system::System,settings::NamedTuple)
    for a in system.assets
        compute_annualized_costs!(a,settings)
    end
end

function compute_annualized_costs!(a::AbstractAsset,settings::NamedTuple)
    for t in fieldnames(typeof(a))
        compute_annualized_costs!(getfield(a, t),settings)
    end
end

function compute_annualized_costs!(y::Union{AbstractEdge,AbstractStorage},settings::NamedTuple)
    if isnothing(annualized_investment_cost(y))
        if iszero(investment_cost(y))
            y.annualized_investment_cost = 0.0
            return nothing
        end
        if ismissing(wacc(y))
            y.wacc = settings.DiscountRate;
        end
        y.annualized_investment_cost = investment_cost(y) * capital_recovery_factor(wacc(y), capital_recovery_period(y));
    end
    return nothing
end

function compute_annualized_costs!(g::Transformation,settings::NamedTuple)
    return nothing
end
function compute_annualized_costs!(n::Node,settings::NamedTuple)
    return nothing
end

function discount_fixed_costs!(system::System, settings::NamedTuple)
    for a in system.assets
        discount_fixed_costs!(a, settings)
    end
end

function discount_fixed_costs!(a::AbstractAsset,settings::NamedTuple)
    for t in fieldnames(typeof(a))
        discount_fixed_costs!(getfield(a, t), settings)
    end
end

function discount_fixed_costs!(y::Union{AbstractEdge,AbstractStorage},settings::NamedTuple)
    
    period_lengths = settings.PeriodLengths
    discount_rate = settings.DiscountRate
    period_idx = period_index(y)
    period_length = period_lengths[period_idx]

    # Number of years of payments that are remaining
    model_years_remaining = years_remaining(period_idx, period_lengths)

    # Myopic expansion only considers costs within the modeled period.
    # Costs that are consequently omitted will be added after the model run when reporting results.
    if isa(settings[:ExpansionHorizon], Myopic)
        payment_years_remaining = min(capital_recovery_period(y), period_length);
    elseif isa(settings[:ExpansionHorizon], PerfectForesight)
        payment_years_remaining = min(capital_recovery_period(y), model_years_remaining);
    else
        # Placeholder for other future cases like rolling horizon
        nothing
    end

    # This PV is relative to the start of the Case, not the start of the period
    y.pv_period_investment_cost = annualized_investment_cost(y) * present_value_annuity_factor(discount_rate, payment_years_remaining)
    
    period_pv_annuity_factor = present_value_annuity_factor(discount_rate, period_length)
    y.pv_period_fixed_om_cost = fixed_om_cost(y) * period_pv_annuity_factor
    y.pv_period_variable_om_cost = variable_om_cost(y) * period_pv_annuity_factor
end

function discount_fixed_costs!(g::Transformation,settings::NamedTuple)
    return nothing
end
function discount_fixed_costs!(n::Node,settings::NamedTuple)
    return nothing
end

function undo_discount_fixed_costs!(system::System, settings::NamedTuple)
    for a in system.assets
        undo_discount_fixed_costs!(a, settings)
    end
end

function undo_discount_fixed_costs!(a::AbstractAsset,settings::NamedTuple)
    for t in fieldnames(typeof(a))
        undo_discount_fixed_costs!(getfield(a, t), settings)
    end
end

function undo_discount_fixed_costs!(y::Union{AbstractEdge,AbstractStorage},settings::NamedTuple)
    
    period_lengths = settings.PeriodLengths
    discount_rate = settings.DiscountRate
    period_idx = period_index(y)

    # Number of years of payments that are remaining
    model_years_remaining = years_remaining(period_idx, period_lengths)
    
    # Include all annuities within the modeling horizon for all cases (including Myopic), since undiscounting only concerns reporting of results 
    payment_years_remaining = min(capital_recovery_period(y), model_years_remaining);

    # y.annualized_investment_cost = payment_years_remaining * annualized_investment_cost(y) * capital_recovery_factor(discount_rate, payment_years_remaining)

    # y.cf_period_investment_cost = payment_years_remaining * annualized_investment_cost(y)
    y.cf_period_investment_cost = payment_years_remaining * pv_period_investment_cost(y) * capital_recovery_factor(discount_rate, payment_years_remaining)
    y.cf_period_fixed_om_cost = period_lengths[period_idx] * fixed_om_cost(y)
    y.cf_period_variable_om_cost = period_lengths[period_idx] * variable_om_cost(y)
end

function undo_discount_fixed_costs!(g::Transformation,settings::NamedTuple)
    return nothing
end
function undo_discount_fixed_costs!(n::Node,settings::NamedTuple)
    return nothing
end

function add_costs_not_seen_by_myopic!(system::System, settings::NamedTuple)
    for a in system.assets
        add_costs_not_seen_by_myopic!(a, settings)
    end
end

function add_costs_not_seen_by_myopic!(y::Union{AbstractEdge,AbstractStorage}, settings::NamedTuple)
    
    period_lengths = settings.PeriodLengths
    discount_rate = settings.DiscountRate
    period_idx = period_index(y)

    model_years_remaining = years_remaining(period_idx, period_lengths)

    k_total  = min(capital_recovery_period(y), model_years_remaining)
    k_myopic = min(capital_recovery_period(y), period_lengths[period_idx])

    total_mult  = present_value_annuity_factor(discount_rate, k_total)
    myopic_mult = present_value_annuity_factor(discount_rate, k_myopic)

    # TODO: We can reorganize this to not need to mutate the pv investment cost
    y.pv_period_investment_cost += annualized_investment_cost(y) * (total_mult - myopic_mult)
end

function add_costs_not_seen_by_myopic!(a::AbstractAsset,settings::NamedTuple)
    for t in fieldnames(typeof(a))
        add_costs_not_seen_by_myopic!(getfield(a, t), settings)
    end
end

function add_costs_not_seen_by_myopic!(g::Transformation,settings::NamedTuple)
    return nothing
end

function add_costs_not_seen_by_myopic!(n::Node,settings::NamedTuple)
    return nothing
end

function validate_existing_capacity(asset::AbstractAsset)
    for t in fieldnames(typeof(asset))
        if isa(getfield(asset, t), AbstractEdge) || isa(getfield(asset, t), AbstractStorage)
            if existing_capacity(getfield(asset, t)) > 0
                msg = " -- Asset with id: \"$(id(asset))\" has existing capacity equal to $(existing_capacity(getfield(asset,t)))"
                msg *= "\nbut it was not present in the previous period. Please double check that the input data is correct."
                @warn(msg)
            end
        end
    end
end

function validate_existing_capacity(component::Union{AbstractEdge,AbstractStorage})
    if existing_capacity(component) > 0
        msg = " -- Component with id: \"$(id(component))\" has existing capacity equal to $(existing_capacity(component))"
        msg *= "\nbut it was not present in the previous period. Please double check that the input data is correct."
        @warn(msg)
    end
    return nothing
end

function create_direct_model_with_optimizer(opt::Optimizer)
    
    if !isnothing(opt.optimizer_env)
        @debug("Setting optimizer with environment $(opt.optimizer_env)")
        try 
            model = direct_model(MOI.instantiate(() -> opt.optimizer(opt.optimizer_env)));
        catch e
            error("Error creating direct_model with optimizer and optimizer environment: $e")
        end
    else
        @debug("Setting optimizer $(opt.optimizer)")
        model = direct_model(MOI.instantiate(opt.optimizer));
    end
    @debug("Setting optimizer attributes $(opt.attributes)")
    
    set_optimizer_attributes(model, opt)

    return model
end
