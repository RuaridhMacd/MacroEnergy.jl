selected_nodes(instance::ProblemInstance) =
    instance.static_system.nodes[instance.spec.node_indices]
selected_unidirectional_edges(instance::ProblemInstance) =
    instance.static_system.unidirectional_edges[instance.spec.unidirectional_edge_indices]
selected_bidirectional_edges(instance::ProblemInstance) =
    instance.static_system.bidirectional_edges[instance.spec.bidirectional_edge_indices]
selected_unit_commitment_edges(instance::ProblemInstance) =
    instance.static_system.unit_commitment_edges[instance.spec.unit_commitment_edge_indices]
selected_transformations(instance::ProblemInstance) =
    instance.static_system.transformations[instance.spec.transformation_indices]
selected_storages(instance::ProblemInstance) =
    instance.static_system.storages[instance.spec.storage_indices]
selected_long_duration_storages(instance::ProblemInstance) =
    instance.static_system.long_duration_storages[instance.spec.long_duration_storage_indices]
selected_edges(instance::ProblemInstance) = vcat(
    selected_unidirectional_edges(instance),
    selected_bidirectional_edges(instance),
    selected_unit_commitment_edges(instance),
)
selected_capacity_components(instance::ProblemInstance) =
    vcat(selected_edges(instance), selected_storages(instance), selected_long_duration_storages(instance))
all_capacity_components(static_system::StaticSystem) = vcat(
    static_system.unidirectional_edges,
    static_system.bidirectional_edges,
    static_system.unit_commitment_edges,
    static_system.storages,
    static_system.long_duration_storages,
)
all_capacity_components(system::System) = vcat(
    edges_with_capacity_variables(get_edges(system)),
    get_storages(system),
)

function initialize_local_state!(instance::ProblemInstance)
    empty!(instance.node_state)
    empty!(instance.unidirectional_edge_state)
    empty!(instance.bidirectional_edge_state)
    empty!(instance.unit_commitment_edge_state)
    empty!(instance.transformation_state)
    empty!(instance.storage_state)
    empty!(instance.long_duration_storage_state)

    local_time_indices = copy(instance.spec.time_indices)

    for idx in instance.spec.node_indices
        instance.node_state[idx] = NodeLocalState(
            global_index = idx,
            local_time_indices = local_time_indices,
        )
    end
    for idx in instance.spec.unidirectional_edge_indices
        instance.unidirectional_edge_state[idx] = EdgeLocalState(
            global_index = idx,
            local_time_indices = local_time_indices,
        )
    end
    for idx in instance.spec.bidirectional_edge_indices
        instance.bidirectional_edge_state[idx] = EdgeLocalState(
            global_index = idx,
            local_time_indices = local_time_indices,
        )
    end
    for idx in instance.spec.unit_commitment_edge_indices
        instance.unit_commitment_edge_state[idx] = EdgeLocalState(
            global_index = idx,
            local_time_indices = local_time_indices,
        )
    end
    for idx in instance.spec.transformation_indices
        instance.transformation_state[idx] = TransformationLocalState(
            global_index = idx,
            local_time_indices = local_time_indices,
        )
    end
    for idx in instance.spec.storage_indices
        instance.storage_state[idx] = StorageLocalState(
            global_index = idx,
            local_time_indices = local_time_indices,
        )
    end
    for idx in instance.spec.long_duration_storage_indices
        instance.long_duration_storage_state[idx] = StorageLocalState(
            global_index = idx,
            local_time_indices = local_time_indices,
        )
    end

    return instance
end

function build_problem_instance(
    static_system::StaticSystem,
    spec_input::Union{Nothing,ProblemSpec};
    id::Symbol=:problem,
)
    instance = ProblemInstance(static_system, spec_input; id)
    initialize_local_state!(instance)
    return instance
end

function build_problem_instance(
    system::System,
    spec_input::Union{Nothing,ProblemSpec};
    id::Symbol=:problem,
)
    return build_problem_instance(StaticSystem(system), spec_input; id)
end

function build_monolithic_problem_instances(case::Case)
    return [
        build_problem_instance(StaticSystem(system), nothing; id=Symbol(:period_, period_idx))
        for (period_idx, system) in enumerate(case.systems)
    ]
end

function build_planning_problem_instances(case::Case)
    return [
        begin
            static_system = StaticSystem(system)
            spec = problem_spec(
                static_system;
                id=Symbol(:planning_period_, period_idx),
                role=:planning,
            )
            build_problem_instance(static_system, spec; id=Symbol(:planning_period_, period_idx))
        end for (period_idx, system) in enumerate(case.systems)
    ]
end

function get_primary_time_data(system::System)
    if haskey(system.time_data, :Electricity)
        return system.time_data[:Electricity]
    end
    return first(values(system.time_data))
end

function get_primary_time_data(static_system::StaticSystem)
    if haskey(static_system.time_data, :Electricity)
        return static_system.time_data[:Electricity]
    end
    return first(values(static_system.time_data))
end

function build_temporal_subproblem_system(
    system::System,
    subperiod_position::Int,
)
    subproblem_system = deepcopy(system)
    primary_time_data = get_primary_time_data(system)
    period_index = primary_time_data.period_index
    subperiod_index = primary_time_data.subperiod_indices[subperiod_position]
    subperiod_interval = primary_time_data.subperiods[subperiod_position]
    subperiod_weight = primary_time_data.subperiod_weights[subperiod_index]
    subperiod_map = primary_time_data.subperiod_map
    modeled_subperiods_all = collect(keys(subperiod_map))
    modeled_subperiods = modeled_subperiods_all[
        findall(subperiod_map[x] == subperiod_index for x in modeled_subperiods_all)
    ]

    for commodity in keys(subproblem_system.time_data)
        time_data = subproblem_system.time_data[commodity]
        time_data.time_interval = subperiod_interval
        time_data.subperiod_weights = Dict(subperiod_index => subperiod_weight)
        time_data.subperiods = [subperiod_interval]
        time_data.subperiod_indices = [subperiod_index]
        time_data.period_index = period_index
        time_data.subperiod_map = Dict(n => subperiod_index for n in modeled_subperiods)
    end

    return (
        system = subproblem_system,
        period_index = period_index,
        subperiod_index = subperiod_index,
        time_indices = collect(subperiod_interval),
        modeled_subperiods = modeled_subperiods,
    )
end

function build_temporal_subproblem_bundles(case::Case)
    bundles = NamedTuple[]
    subproblem_count = 0

    for (period_idx, system) in enumerate(case.systems)
        primary_time_data = get_primary_time_data(system)
        for subperiod_position in eachindex(primary_time_data.subperiods)
            subproblem_count += 1
            subproblem_data = build_temporal_subproblem_system(system, subperiod_position)
            static_system = StaticSystem(subproblem_data.system)
            spec = problem_spec(
                static_system;
                id=Symbol(:subproblem_, subproblem_count),
                role=:temporal_subproblem,
                time_indices=subproblem_data.time_indices,
                metadata=Dict{Symbol,Any}(
                    :period_index => period_idx,
                    :subproblem_index => subproblem_count,
                    :subperiod_index => subproblem_data.subperiod_index,
                    :modeled_subperiods => subproblem_data.modeled_subperiods,
                ),
            )
            instance = build_problem_instance(
                static_system,
                spec;
                id=Symbol(:subproblem_, subproblem_count),
            )
            push!(
                bundles,
                (
                    system = subproblem_data.system,
                    instance = instance,
                    period_index = period_idx,
                    subproblem_index = subproblem_count,
                    subperiod_index = subproblem_data.subperiod_index,
                ),
            )
        end
    end

    return bundles
end

function create_problem_model(instance::ProblemInstance)
    model = Model()
    set_string_names_on_creation(model, instance.static_system.settings.EnableJuMPStringNames)
    return model
end

function create_named_problem_model(instance::ProblemInstance)
    model = Model()
    set_string_names_on_creation(model, true)
    return model
end

function create_problem_model(instance::ProblemInstance, opt::Optimizer)
    if instance.static_system.settings.EnableJuMPDirectModel
        model = create_direct_model_with_optimizer(opt)
    else
        model = create_problem_model(instance)
        set_optimizer(model, opt)
    end

    set_string_names_on_creation(model, instance.static_system.settings.EnableJuMPStringNames)
    return model
end

function create_named_problem_model(instance::ProblemInstance, opt::Optimizer)
    if instance.static_system.settings.EnableJuMPDirectModel
        model = create_direct_model_with_optimizer(opt)
    else
        model = create_named_problem_model(instance)
        set_optimizer(model, opt)
    end

    set_string_names_on_creation(model, true)
    return model
end

function add_linking_variables!(instance::ProblemInstance, model::Model)
    for node in selected_nodes(instance)
        add_linking_variables!(node, model)
    end
    for transformation in selected_transformations(instance)
        add_linking_variables!(transformation, model)
    end
    for storage in selected_storages(instance)
        add_linking_variables!(storage, model)
    end
    for storage in selected_long_duration_storages(instance)
        add_linking_variables!(storage, model)
    end
    for edge in selected_unidirectional_edges(instance)
        add_linking_variables!(edge, model)
    end
    for edge in selected_bidirectional_edges(instance)
        add_linking_variables!(edge, model)
    end
    for edge in selected_unit_commitment_edges(instance)
        add_linking_variables!(edge, model)
    end
    return nothing
end

function define_available_capacity!(instance::ProblemInstance, model::Model)
    for node in selected_nodes(instance)
        define_available_capacity!(node, model)
    end
    for transformation in selected_transformations(instance)
        define_available_capacity!(transformation, model)
    end
    for storage in selected_storages(instance)
        define_available_capacity!(storage, model)
    end
    for storage in selected_long_duration_storages(instance)
        define_available_capacity!(storage, model)
    end
    for edge in selected_unidirectional_edges(instance)
        define_available_capacity!(edge, model)
    end
    for edge in selected_bidirectional_edges(instance)
        define_available_capacity!(edge, model)
    end
    for edge in selected_unit_commitment_edges(instance)
        define_available_capacity!(edge, model)
    end
    return nothing
end

function planning_model!(instance::ProblemInstance, model::Model)
    for node in selected_nodes(instance)
        planning_model!(node, model)
    end
    for transformation in selected_transformations(instance)
        planning_model!(transformation, model)
    end
    for storage in selected_storages(instance)
        planning_model!(storage, model)
    end
    for storage in selected_long_duration_storages(instance)
        planning_model!(storage, model)
    end
    for edge in selected_unidirectional_edges(instance)
        planning_model!(edge, model)
    end
    for edge in selected_bidirectional_edges(instance)
        planning_model!(edge, model)
    end
    for edge in selected_unit_commitment_edges(instance)
        planning_model!(edge, model)
    end

    add_constraints_by_type!(instance, model, PlanningConstraint)
    return nothing
end

function operation_model!(instance::ProblemInstance, model::Model)
    for node in selected_nodes(instance)
        operation_model!(node, model)
    end
    for transformation in selected_transformations(instance)
        operation_model!(transformation, model)
    end
    for storage in selected_storages(instance)
        operation_model!(storage, model)
    end
    for storage in selected_long_duration_storages(instance)
        operation_model!(storage, model)
    end
    for edge in selected_unidirectional_edges(instance)
        operation_model!(edge, model)
    end
    for edge in selected_bidirectional_edges(instance)
        operation_model!(edge, model)
    end
    for edge in selected_unit_commitment_edges(instance)
        operation_model!(edge, model)
    end

    add_constraints_by_type!(instance, model, OperationConstraint)
    return nothing
end

function add_constraints_by_type!(instance::ProblemInstance, model::Model, constraint_type::DataType)
    for node in selected_nodes(instance)
        add_constraints_by_type!(node, model, constraint_type)
    end
    for transformation in selected_transformations(instance)
        add_constraints_by_type!(transformation, model, constraint_type)
    end
    for storage in selected_storages(instance)
        add_constraints_by_type!(storage, model, constraint_type)
    end
    for storage in selected_long_duration_storages(instance)
        add_constraints_by_type!(storage, model, constraint_type)
    end
    for edge in selected_unidirectional_edges(instance)
        add_constraints_by_type!(edge, model, constraint_type)
    end
    for edge in selected_bidirectional_edges(instance)
        add_constraints_by_type!(edge, model, constraint_type)
    end
    for edge in selected_unit_commitment_edges(instance)
        add_constraints_by_type!(edge, model, constraint_type)
    end
    return nothing
end

function add_age_based_retirements!(instance::ProblemInstance, model::Model)
    for storage in selected_storages(instance)
        if retirement_period(storage) > 0 || min_retired_capacity_track(storage) > 0.0
            push!(storage.constraints, AgeBasedRetirementConstraint())
            add_model_constraint!(storage.constraints[end], storage, model)
        end
    end
    for storage in selected_long_duration_storages(instance)
        if retirement_period(storage) > 0 || min_retired_capacity_track(storage) > 0.0
            push!(storage.constraints, AgeBasedRetirementConstraint())
            add_model_constraint!(storage.constraints[end], storage, model)
        end
    end
    for edge in selected_unidirectional_edges(instance)
        if retirement_period(edge) > 0 || min_retired_capacity_track(edge) > 0.0
            push!(edge.constraints, AgeBasedRetirementConstraint())
            add_model_constraint!(edge.constraints[end], edge, model)
        end
    end
    for edge in selected_bidirectional_edges(instance)
        if retirement_period(edge) > 0 || min_retired_capacity_track(edge) > 0.0
            push!(edge.constraints, AgeBasedRetirementConstraint())
            add_model_constraint!(edge.constraints[end], edge, model)
        end
    end
    for edge in selected_unit_commitment_edges(instance)
        if retirement_period(edge) > 0 || min_retired_capacity_track(edge) > 0.0
            push!(edge.constraints, AgeBasedRetirementConstraint())
            add_model_constraint!(edge.constraints[end], edge, model)
        end
    end
    return nothing
end

function add_feasibility_constraints!(instance::ProblemInstance, model::Model)
    for storage in selected_long_duration_storages(instance)
        has_storage_max_level_constraint = any(isa.(storage.constraints, MaxStorageLevelConstraint))
        has_storage_min_level_constraint = any(isa.(storage.constraints, MinStorageLevelConstraint))
        has_init_storage_max_level_constraint = any(isa.(storage.constraints, MaxInitStorageLevelConstraint))
        has_init_storage_min_level_constraint = any(isa.(storage.constraints, MinInitStorageLevelConstraint))

        if has_storage_max_level_constraint && !has_init_storage_max_level_constraint
            @info("Adding max initial storage level constraint to storage $(id(storage)) for feasibility")
            push!(storage.constraints, MaxInitStorageLevelConstraint())
            add_model_constraint!(storage.constraints[end], storage, model)
        end

        if has_storage_min_level_constraint && !has_init_storage_min_level_constraint
            @info("Adding min initial storage level constraint to storage $(id(storage)) for feasibility")
            push!(storage.constraints, MinInitStorageLevelConstraint())
            add_model_constraint!(storage.constraints[end], storage, model)
        end
    end

    return nothing
end

function get_available_capacity(instances::Vector{ProblemInstance})
    available_capacity = Dict{Tuple{Symbol,Int64},Union{JuMPVariable,AffExpr}}()
    for instance in instances
        get_available_capacity!(instance, available_capacity)
    end
    return available_capacity
end

function get_available_capacity!(
    instance::ProblemInstance,
    available_capacity::Dict{Tuple{Symbol,Int64},Union{JuMPVariable,AffExpr}},
)
    for storage in selected_storages(instance)
        available_capacity[storage.id, period_index(storage)] = storage.capacity
    end
    for storage in selected_long_duration_storages(instance)
        available_capacity[storage.id, period_index(storage)] = storage.capacity
    end
    for edge in selected_edges(instance)
        available_capacity[edge.id, period_index(edge)] = edge.capacity
    end
    return available_capacity
end

function populate_planning_problem!(
    instance::ProblemInstance,
    model::Model;
    period_idx::Union{Int,Nothing}=nothing,
)
    @info(" -- Adding linking variables")
    add_linking_variables!(instance, model)

    @info(" -- Defining available capacity")
    define_available_capacity!(instance, model)

    @info(" -- Generating planning model")
    planning_model!(instance, model)

    if instance.static_system.settings.Retrofitting
        isnothing(period_idx) &&
            error("A period index is required to add retrofit constraints for a planning problem.")
        @info(" -- Adding retrofit constraints")
        add_retrofit_constraints!(instance, period_idx, model)
    end

    @info(" -- Including age-based retirements")
    add_age_based_retirements!(instance, model)

    add_feasibility_constraints!(instance, model)

    return nothing
end

function populate_operation_problem!(instance::ProblemInstance, model::Model)
    add_linking_variables!(instance, model)
    define_available_capacity!(instance, model)
    operation_model!(instance, model)
    return nothing
end

function get_retrofit_edges(instance::ProblemInstance)
    can_retrofit_edges = Dict{Symbol,AbstractEdge}()
    is_retrofit_edges = Dict{Symbol,AbstractEdge}()
    for edge in selected_edges(instance)
        if can_retrofit(edge) && !ismissing(retrofit_id(edge))
            can_retrofit_edges[edge.id] = edge
        end
        if is_retrofit(edge) && !ismissing(retrofit_id(edge))
            is_retrofit_edges[retrofit_id(edge)[1]] = edge
        end
    end
    return can_retrofit_edges, is_retrofit_edges
end

function add_retrofit_constraints!(instance::ProblemInstance, period_idx::Int, model::Model)
    can_retrofit_edges, is_retrofit_edges = get_retrofit_edges(instance)
    isempty(can_retrofit_edges) && return nothing

    @constraint(
        model,
        [edge_id in keys(can_retrofit_edges)],
        retrofitted_capacity(can_retrofit_edges[edge_id]) ==
        sum(
            new_capacity(is_retrofit_edges[retrofit_id]) / retrofit_efficiency(is_retrofit_edges[retrofit_id])
            for retrofit_id in retrofit_id(can_retrofit_edges[edge_id])
        ),
        base_name = "cRetrofitCapacity_period$(period_idx)",
    )

    return nothing
end

function validate_existing_capacity(y::Union{AbstractEdge,AbstractStorage})
    if existing_capacity(y) > 0
        msg = " -- Component with id: \"$(id(y))\" has existing capacity equal to $(existing_capacity(y))"
        msg *= "\nbut it was not present in the previous period. Please double check that the input data is correct."
        @warn(msg)
    end
    return nothing
end

function carry_over_capacities!(
    instance::ProblemInstance,
    instance_prev::ProblemInstance;
    perfect_foresight::Bool=true,
)
    prev_components = Dict(id(y) => y for y in selected_capacity_components(instance_prev))

    for y in selected_capacity_components(instance)
        y_prev = get(prev_components, id(y), nothing)
        if isnothing(y_prev)
            @info("Skipping component $(id(y)) as it was not present in the previous period")
            validate_existing_capacity(y)
        else
            carry_over_capacities!(y, y_prev; perfect_foresight)
        end
    end

    return nothing
end

function carry_over_capacities!(
    system::System,
    instance_prev::ProblemInstance;
    perfect_foresight::Bool=true,
)
    prev_components = Dict(id(y) => y for y in selected_capacity_components(instance_prev))

    for y in all_capacity_components(system)
        y_prev = get(prev_components, id(y), nothing)
        if isnothing(y_prev)
            @info("Skipping component $(id(y)) as it was not present in the previous period")
            validate_existing_capacity(y)
        else
            carry_over_capacities!(y, y_prev; perfect_foresight)
        end
    end

    return nothing
end

function populate_problem_model!(
    instance::ProblemInstance,
    model::Model;
    period_idx::Union{Int,Nothing}=nothing,
)
    populate_planning_problem!(instance, model; period_idx)
    @info(" -- Generating operational model")
    operation_model!(instance, model)

    return nothing
end

function build_monolithic_model(case::Case, opt::Optimizer)
    problem_instances = build_monolithic_problem_instances(case)
    model = create_problem_model(problem_instances[1], opt)
    settings = get_settings(case)
    num_periods = length(problem_instances)

    @info("Generating model")

    start_time = time()

    @variable(model, vREF == 1)

    fixed_cost = Dict()
    om_fixed_cost = Dict()
    investment_cost = Dict()
    variable_cost = Dict()

    for (period_idx, instance) in enumerate(problem_instances)
        @info(" -- Period $period_idx")

        model[:eFixedCost] = AffExpr(0.0)
        model[:eInvestmentFixedCost] = AffExpr(0.0)
        model[:eOMFixedCost] = AffExpr(0.0)
        model[:eVariableCost] = AffExpr(0.0)

        populate_problem_model!(instance, model; period_idx)

        if period_idx < num_periods
            @info(
                " -- Available capacity in period $(period_idx) is being carried over to period $(period_idx+1)",
            )
            carry_over_capacities!(problem_instances[period_idx + 1], instance)
        end

        model[:eFixedCost] = model[:eInvestmentFixedCost] + model[:eOMFixedCost]
        fixed_cost[period_idx] = model[:eFixedCost]
        investment_cost[period_idx] = model[:eInvestmentFixedCost]
        om_fixed_cost[period_idx] = model[:eOMFixedCost]
        unregister(model, :eFixedCost)
        unregister(model, :eInvestmentFixedCost)
        unregister(model, :eOMFixedCost)

        variable_cost[period_idx] = model[:eVariableCost]
        unregister(model, :eVariableCost)
    end

    period_lengths = collect(settings.PeriodLengths)
    discount_rate = settings.DiscountRate
    discount_factor = present_value_factor(discount_rate, period_lengths)

    @expression(model, eFixedCostByPeriod[s in 1:num_periods], discount_factor[s] * fixed_cost[s])
    @expression(
        model,
        eInvestmentFixedCostByPeriod[s in 1:num_periods],
        discount_factor[s] * investment_cost[s],
    )
    @expression(model, eOMFixedCostByPeriod[s in 1:num_periods], discount_factor[s] * om_fixed_cost[s])
    @expression(model, eFixedCost, sum(eFixedCostByPeriod[s] for s in 1:num_periods))

    opexmult = present_value_annuity_factor.(discount_rate, period_lengths)
    @expression(
        model,
        eVariableCostByPeriod[s in 1:num_periods],
        discount_factor[s] * opexmult[s] * variable_cost[s],
    )
    @expression(model, eVariableCost, sum(eVariableCostByPeriod[s] for s in 1:num_periods))

    @objective(model, Min, model[:eFixedCost] + model[:eVariableCost])

    @info(" -- Model generation complete, it took $(time() - start_time) seconds")

    return model
end
