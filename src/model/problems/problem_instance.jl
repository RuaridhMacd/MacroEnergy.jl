Base.@kwdef mutable struct ProblemInstance
    id::Symbol
    static_system::StaticSystem
    spec::ProblemSpec
    model::Model = Model()
    node_state::Dict{Int,NodeLocalState} = Dict{Int,NodeLocalState}()
    unidirectional_edge_state::Dict{Int,EdgeLocalState} = Dict{Int,EdgeLocalState}()
    bidirectional_edge_state::Dict{Int,EdgeLocalState} = Dict{Int,EdgeLocalState}()
    unit_commitment_edge_state::Dict{Int,EdgeLocalState} = Dict{Int,EdgeLocalState}()
    transformation_state::Dict{Int,TransformationLocalState} = Dict{Int,TransformationLocalState}()
    storage_state::Dict{Int,StorageLocalState} = Dict{Int,StorageLocalState}()
    long_duration_storage_state::Dict{Int,StorageLocalState} = Dict{Int,StorageLocalState}()
    update_map::UpdateMap = UpdateMap()
    reassembly_map::ReassemblyMap = ReassemblyMap()
end

function ProblemInstance(static_system::StaticSystem, spec_input::Union{Nothing,ProblemSpec}; id::Symbol=:problem)
    spec = normalize_problem_spec(static_system, spec_input)
    return ProblemInstance(
        id = id,
        static_system = static_system,
        spec = spec,
    )
end

find_component_global_index(components, component) = findfirst(x -> x === component, components)

function get_component_global_index(components, component)
    global_index = find_component_global_index(components, component)
    isnothing(global_index) &&
        error("Component $(typeof(component)) with id $(id(component)) is not part of problem $(component).")
    return global_index
end

get_local_state(instance::ProblemInstance, node::Node) =
    instance.node_state[get_component_global_index(instance.static_system.nodes, node)]
get_local_state(instance::ProblemInstance, edge::UnidirectionalEdge) =
    instance.unidirectional_edge_state[
        get_component_global_index(instance.static_system.unidirectional_edges, edge)
    ]
get_local_state(instance::ProblemInstance, edge::BidirectionalEdge) =
    instance.bidirectional_edge_state[
        get_component_global_index(instance.static_system.bidirectional_edges, edge)
    ]
get_local_state(instance::ProblemInstance, edge::EdgeWithUC) =
    instance.unit_commitment_edge_state[
        get_component_global_index(instance.static_system.unit_commitment_edges, edge)
    ]
get_local_state(instance::ProblemInstance, transformation::Transformation) =
    instance.transformation_state[
        get_component_global_index(instance.static_system.transformations, transformation)
    ]
get_local_state(instance::ProblemInstance, storage::Storage) =
    instance.storage_state[
        get_component_global_index(instance.static_system.storages, storage)
    ]
get_local_state(instance::ProblemInstance, storage::LongDurationStorage) =
    instance.long_duration_storage_state[
        get_component_global_index(instance.static_system.long_duration_storages, storage)
    ]

function maybe_get_local_state(instance::ProblemInstance, node::Node)
    global_index = find_component_global_index(instance.static_system.nodes, node)
    return isnothing(global_index) ? nothing : get(instance.node_state, global_index, nothing)
end
function maybe_get_local_state(instance::ProblemInstance, edge::UnidirectionalEdge)
    global_index = find_component_global_index(instance.static_system.unidirectional_edges, edge)
    return isnothing(global_index) ? nothing : get(instance.unidirectional_edge_state, global_index, nothing)
end
function maybe_get_local_state(instance::ProblemInstance, edge::BidirectionalEdge)
    global_index = find_component_global_index(instance.static_system.bidirectional_edges, edge)
    return isnothing(global_index) ? nothing : get(instance.bidirectional_edge_state, global_index, nothing)
end
function maybe_get_local_state(instance::ProblemInstance, edge::EdgeWithUC)
    global_index = find_component_global_index(instance.static_system.unit_commitment_edges, edge)
    return isnothing(global_index) ? nothing : get(instance.unit_commitment_edge_state, global_index, nothing)
end
function maybe_get_local_state(instance::ProblemInstance, transformation::Transformation)
    global_index = find_component_global_index(instance.static_system.transformations, transformation)
    return isnothing(global_index) ? nothing : get(instance.transformation_state, global_index, nothing)
end
function maybe_get_local_state(instance::ProblemInstance, storage::Storage)
    global_index = find_component_global_index(instance.static_system.storages, storage)
    return isnothing(global_index) ? nothing : get(instance.storage_state, global_index, nothing)
end
function maybe_get_local_state(instance::ProblemInstance, storage::LongDurationStorage)
    global_index = find_component_global_index(instance.static_system.long_duration_storages, storage)
    return isnothing(global_index) ? nothing : get(instance.long_duration_storage_state, global_index, nothing)
end

function apply_planning_solution!(
    instance::ProblemInstance,
    planning_variable_values::AbstractDict;
    kind::Union{Nothing,Symbol}=:fix,
)
    apply_updates!(instance.update_map, planning_variable_values; kind)
    return nothing
end

capture_numeric_payload(payload::VariableRef) = JuMP.value(payload)
capture_numeric_payload(payload::JuMP.Containers.DenseAxisArray) = JuMP.value.(payload)
capture_numeric_payload(payload::AbstractArray) = JuMP.value.(payload)
capture_numeric_payload(payload::AbstractDict) =
    Dict(key => capture_numeric_payload(item) for (key, item) in pairs(payload))
capture_numeric_payload(payload) = payload

function capture_problem_solution_values!(instance::ProblemInstance)
    for (idx, state) in pairs(instance.node_state)
        capture_node_solution_values!(state, instance.static_system.nodes[idx])
    end
    for state in values(instance.unidirectional_edge_state)
        capture_edge_solution_values!(state)
    end
    for state in values(instance.bidirectional_edge_state)
        capture_edge_solution_values!(state)
    end
    for state in values(instance.unit_commitment_edge_state)
        capture_edge_solution_values!(state)
    end
    for state in values(instance.storage_state)
        capture_storage_solution_values!(state)
    end
    for state in values(instance.long_duration_storage_state)
        capture_storage_solution_values!(state)
    end
    return instance
end

function capture_node_solution_values!(state::NodeLocalState, node::Node)
    for key in (:non_served_demand, :policy_budgeting_vars, :policy_slack_vars, :supply_flow)
        if haskey(state.variables, key)
            state.values[key] = capture_numeric_payload(state.variables[key])
        end
    end
    if haskey(state.constraints, :balance_constraint)
        balance_constraint = state.constraints[:balance_constraint]
        if ismissing(constraint_dual(balance_constraint)) && !ismissing(constraint_ref(balance_constraint))
            set_constraint_dual!(balance_constraint, node)
        end
        if !ismissing(constraint_dual(balance_constraint))
            state.values[:balance_dual] = copy(constraint_dual(balance_constraint))
        end
    end
    return state
end

function capture_edge_solution_values!(state::EdgeLocalState)
    for key in (:capacity, :new_capacity, :retired_capacity, :retrofitted_capacity, :flow, :ucommit, :ustart, :ushut)
        if haskey(state.variables, key)
            state.values[key] = capture_numeric_payload(state.variables[key])
        end
    end
    return state
end

function capture_storage_solution_values!(state::StorageLocalState)
    for key in (:capacity, :new_capacity, :retired_capacity, :storage_level, :storage_initial, :storage_change)
        if haskey(state.variables, key)
            state.values[key] = capture_numeric_payload(state.variables[key])
        end
    end
    return state
end
