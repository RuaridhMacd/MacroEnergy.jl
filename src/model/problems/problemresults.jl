function result_value(ref)
    return value(ref)
end

result_value(ref::Number) = Float64(ref)

function result_value(refs::Union{AbstractArray,JuMP.Containers.DenseAxisArray,JuMP.Containers.SparseAxisArray})
    return value.(refs)
end

function result_array(refs)
    values = result_value(refs)
    return hasproperty(values, :data) ? copy(values.data) : Array(values)
end

function result_vector(refs)
    return Float64.(vec(result_array(refs)))
end

function result_matrix(refs)
    return Matrix{Float64}(result_array(refs))
end

function result_value(refs::AbstractDict)
    return Dict(key => result_value(ref) for (key, ref) in refs)
end

function result_expression_dict(expressions::AbstractDict)
    return Dict(key => result_vector(expr) for (key, expr) in expressions)
end

function assign_result!(set!, ref)
    isnothing(ref) && return nothing
    set!(result_value(ref))
    return nothing
end

function assign_vector_result!(set!, ref)
    isnothing(ref) && return nothing
    set!(result_vector(ref))
    return nothing
end

function assign_matrix_result!(set!, ref)
    isnothing(ref) && return nothing
    set!(result_matrix(ref))
    return nothing
end

function result_dict(ref, indices)
    isnothing(ref) && return Dict{Int64,Float64}()
    return Dict{Int64,Float64}(idx => Float64(value(ref[idx])) for idx in indices)
end

function constraint_dual_vector(ref)
    values = dual.(ref)
    values isa Number && return [Float64(values)]
    values = hasproperty(values, :data) ? values.data : values
    return Float64.(vec(values))
end

function populate_constraint_dual!(::AbstractTypeConstraint, component, refs)
    return nothing
end

function populate_constraint_dual!(
    constraint::BalanceConstraint,
    vertex::AbstractVertex,
    refs::Union{NodeRefs,TransformationRefs,StorageRefs},
)
    ref = get(refs.constraints, BalanceConstraint, nothing)
    isnothing(ref) && return nothing

    constraint.constraint_dual = Dict{Symbol,Vector{Float64}}()
    for balance_id in balance_ids(vertex)
        constraint.constraint_dual[balance_id] = constraint_dual_vector(ref[balance_id, :])
    end

    return nothing
end

function populate_constraint_dual!(constraint::PolicyConstraint, node::Node, refs::NodeRefs)
    ref = get(refs.constraints, typeof(constraint), nothing)
    isnothing(ref) && return nothing
    constraint.constraint_dual = constraint_dual_vector(ref)
    return nothing
end

function populate_constraint_duals!(component::Union{AbstractVertex,AbstractEdge}, refs)
    for constraint in all_constraints(component)
        populate_constraint_dual!(constraint, component, refs)
    end
    return nothing
end

function populate_vertex_results!(vertex::AbstractVertex, refs::Union{NodeRefs,TransformationRefs,StorageRefs})
    vertex.operation_expr = result_expression_dict(refs.expressions)
    populate_constraint_duals!(vertex, refs)
    return nothing
end

function populate_common_edge_results!(edge::AbstractEdge, refs::Union{EdgeRefs,EdgeWithUCRefs})
    assign_result!(value -> edge.capacity = value, refs.capacity)
    assign_result!(value -> edge.existing_capacity = value, refs.existing_capacity)
    assign_result!(value -> edge.new_units = value, refs.new_units)
    assign_result!(value -> begin
        edge.new_capacity = value
        edge.new_capacity_track[period_index(edge)] = value
    end, refs.new_capacity)
    assign_result!(value -> edge.retired_units = value, refs.retired_units)
    assign_result!(value -> begin
        edge.retired_capacity = value
        edge.retired_capacity_track[period_index(edge)] = value
    end, refs.retired_capacity)
    assign_result!(value -> edge.retrofitted_units = value, refs.retrofitted_units)
    assign_result!(value -> begin
        edge.retrofitted_capacity = value
        edge.retrofitted_capacity_track[period_index(edge)] = value
    end, refs.retrofitted_capacity)
    assign_vector_result!(value -> edge.flow = value, refs.flow)
    return nothing
end

function populate_results!(node::Node, refs::NodeRefs)
    populate_vertex_results!(node, refs)

    assign_matrix_result!(value -> node.non_served_demand = value, refs.non_served_demand)
    assign_matrix_result!(value -> node.supply_flow = value, refs.supply_flow)

    for (key, ref) in refs.policy_budgeting_vars
        node.policy_budgeting_vars[key] = result_vector(ref)
    end

    for (key, ref) in refs.policy_slack_vars
        node.policy_slack_vars[key] = result_vector(ref)
    end

    for (key, ref) in refs.policy_budgeting_constraints
        node.policy_budgeting_constraints[key] = constraint_dual_vector(ref)
    end

    return nothing
end

function populate_results!(edge::UnidirectionalEdge, refs::UnidirectionalEdgeRefs)
    return populate_common_edge_results!(edge, refs.edge)
end

function populate_results!(edge::BidirectionalEdge, refs::BidirectionalEdgeRefs)
    return populate_common_edge_results!(edge, refs.edge)
end

function populate_results!(edge::EdgeWithUC, refs::EdgeWithUCRefs)
    populate_common_edge_results!(edge, refs)
    assign_vector_result!(value -> edge.ucommit = value, refs.ucommit)
    assign_vector_result!(value -> edge.ustart = value, refs.ustart)
    assign_vector_result!(value -> edge.ushut = value, refs.ushut)
    return nothing
end

function populate_results!(transformation::Transformation, refs::TransformationRefs)
    populate_vertex_results!(transformation, refs)
    return nothing
end

function populate_common_storage_results!(storage::AbstractStorage, refs::StorageRefs)
    populate_vertex_results!(storage, refs)
    assign_result!(value -> storage.capacity = value, refs.capacity)
    assign_result!(value -> storage.existing_capacity = value, refs.existing_capacity)
    assign_result!(value -> storage.new_units = value, refs.new_units)
    assign_result!(value -> begin
        storage.new_capacity = value
        storage.new_capacity_track[period_index(storage)] = value
    end, refs.new_capacity)
    assign_result!(value -> storage.retired_units = value, refs.retired_units)
    assign_result!(value -> begin
        storage.retired_capacity = value
        storage.retired_capacity_track[period_index(storage)] = value
    end, refs.retired_capacity)
    assign_vector_result!(value -> storage.storage_level = value, refs.storage_level)
    return nothing
end

function populate_results!(storage::Storage, refs::StorageRefs)
    return populate_common_storage_results!(storage, refs)
end

function populate_results!(storage::LongDurationStorage, refs::StorageRefs)
    populate_common_storage_results!(storage, refs)
    storage.storage_initial = result_dict(refs.storage_initial, modeled_subperiods(storage))
    storage.storage_change = result_dict(refs.storage_change, subperiod_indices(storage))
    return nothing
end

function populate_results!(system::StaticSystem, problem::Problem)
    foreach_problem_component!(system, problem) do component, refs
        populate_results!(component, refs)
    end
    return nothing
end

function populate_results!(systems::AbstractVector{StaticSystem}, problem::Problem)
    foreach_problem_component!(systems, problem) do component, refs
        populate_results!(component, refs)
    end
    return nothing
end

populate_results!(::StaticSystem, ::Model) = nothing
populate_results!(::System, ::Model) = nothing

function populate_results!(system::System, problem::Problem)
    return populate_results!(StaticSystem(system), problem)
end

function populate_results!(case::Case, problem::Problem)
    return populate_results!(StaticSystem.(get_periods(case)), problem)
end

populate_results!(::Case, ::Model) = nothing

function populate_results!(case::Case, problem::BendersProblem)
    isnothing(problem.planning_sol) && return nothing
    return populate_planning_results!(StaticSystem.(get_periods(case)), problem)
end

function populate_results!(system::System, problem::BendersProblem)
    isnothing(problem.planning_sol) && return nothing
    return populate_planning_results!(StaticSystem(system), problem)
end

populate_results!(::Case, ::BendersModel) = nothing
populate_results!(::System, ::BendersModel) = nothing

function populate_planning_results!(systems, problem::Problem, planning_sol::NamedTuple)
    values_by_ref = Dict(ref => planning_sol.values[key] for (key, ref) in planning_sol.refs)
    foreach_problem_component!(systems, problem) do component, refs
        populate_planning_results!(component, refs, values_by_ref)
    end
    return nothing
end

function populate_planning_results!(systems, problem::BendersProblem)
    values_by_ref = benders_planning_values_by_ref(problem)
    foreach_problem_component!(systems, problem.planning) do component, refs
        populate_planning_results!(component, refs, values_by_ref)
    end
    return nothing
end

function benders_planning_values_by_ref(problem::BendersProblem)
    values_by_ref = Dict{VariableRef,Float64}()
    for variable in problem.planning_variables
        value = benders_planning_value(problem.planning_sol.values, variable)
        isnothing(value) && continue
        values_by_ref[getproperty(variable, :ref)] = Float64(value)
    end
    return values_by_ref
end

function benders_planning_value(values::AbstractDict, variable)
    key = getproperty(variable, :key)
    haskey(values, key) && return values[key]
    key isa VariableRef || return nothing

    key_name = JuMP.name(key)
    for (candidate, value) in values
        candidate isa VariableRef || continue
        JuMP.name(candidate) == key_name && return value
    end
    return nothing
end

populate_planning_results!(::Transformation, ::TransformationRefs, ::Dict) = nothing

function populate_planning_results!(node::Node, refs::NodeRefs, values_by_ref::Dict)
    for (name, variables) in refs.policy_budgeting_vars
        node.policy_budgeting_vars[name] = [solution_value(values_by_ref, variables[w]) for w in subperiod_indices(node)]
    end
    return nothing
end

function populate_planning_results!(
    component::Union{AbstractEdge,AbstractStorage},
    refs,
    values_by_ref::Dict,
)
    populate_capacity_planning_results!(component, refs, values_by_ref)
    return nothing
end

function populate_capacity_planning_results!(
    component::Union{AbstractEdge,AbstractStorage},
    refs,
    values_by_ref::Dict,
)
    capacity_ref = capacity_refs(refs)
    has_capacity(component) || return nothing

    component.capacity = solution_value(values_by_ref, capacity(capacity_ref))
    component.new_capacity = solution_value(values_by_ref, new_capacity(capacity_ref))
    component.retired_capacity = solution_value(values_by_ref, retired_capacity(capacity_ref))
    component.new_capacity_track[period_index(component)] = component.new_capacity
    component.retired_capacity_track[period_index(component)] = component.retired_capacity

    if component isa AbstractEdge
        component.retrofitted_capacity = solution_value(values_by_ref, retrofitted_capacity(capacity_ref))
        component.retrofitted_capacity_track[period_index(component)] = component.retrofitted_capacity
    end

    return nothing
end

function populate_planning_results!(storage::LongDurationStorage, refs::StorageRefs, values_by_ref::Dict)
    populate_capacity_planning_results!(storage, refs, values_by_ref)
    storage.storage_initial = Dict(
        r => solution_value(values_by_ref, refs.storage_initial[r])
        for r in modeled_subperiods(storage)
    )
    storage.storage_change = Dict(
        w => solution_value(values_by_ref, refs.storage_change[w])
        for w in subperiod_indices(storage)
    )
    return nothing
end

solution_value(::Dict, value::Number) = Float64(value)
solution_value(values_by_ref::Dict, value) = JuMP.value(ref -> values_by_ref[ref], value)
solution_value(::Dict, ::Nothing) = 0.0
