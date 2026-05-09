Base.@kwdef struct ComponentRefKey
    field::Symbol
    index::Int
end

Base.@kwdef mutable struct NodeRefs
    component_index::Int
    non_served_demand::Any = nothing
    supply_flow::Any = nothing
    policy_budgeting_vars::Dict{Symbol,Any} = Dict{Symbol,Any}()
    policy_budgeting_constraints::Dict{DataType,Any} = Dict{DataType,Any}()
    policy_slack_vars::Dict{Symbol,Any} = Dict{Symbol,Any}()
    constraints::Dict{Any,Any} = Dict{Any,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct EdgeRefs
    component_index::Int
    start_vertex_ref::Union{Nothing,ComponentRefKey} = nothing
    end_vertex_ref::Union{Nothing,ComponentRefKey} = nothing
    capacity::Any = nothing
    new_units::Any = nothing
    new_capacity::Any = nothing
    retired_units::Any = nothing
    retired_capacity::Any = nothing
    retrofitted_units::Any = nothing
    retrofitted_capacity::Any = nothing
    flow::Any = nothing
    constraints::Dict{Any,Any} = Dict{Any,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct UnidirectionalEdgeRefs
    edge::EdgeRefs
end

Base.@kwdef mutable struct BidirectionalEdgeRefs
    edge::EdgeRefs
    flow_pos::Any = nothing
    flow_neg::Any = nothing
end

Base.@kwdef mutable struct EdgeWithUCRefs
    component_index::Int
    start_vertex_ref::Union{Nothing,ComponentRefKey} = nothing
    end_vertex_ref::Union{Nothing,ComponentRefKey} = nothing
    capacity::Any = nothing
    new_units::Any = nothing
    new_capacity::Any = nothing
    retired_units::Any = nothing
    retired_capacity::Any = nothing
    retrofitted_units::Any = nothing
    retrofitted_capacity::Any = nothing
    flow::Any = nothing
    ucommit::Any = nothing
    ustart::Any = nothing
    ushut::Any = nothing
    constraints::Dict{Any,Any} = Dict{Any,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct TransformationRefs
    component_index::Int
    constraints::Dict{Any,Any} = Dict{Any,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct StorageRefs
    component_index::Int
    charge_edge_ref::Union{Nothing,ComponentRefKey} = nothing
    discharge_edge_ref::Union{Nothing,ComponentRefKey} = nothing
    spillage_edge_ref::Union{Nothing,ComponentRefKey} = nothing
    charge_edge_id::Union{Nothing,Symbol} = nothing
    discharge_edge_id::Union{Nothing,Symbol} = nothing
    spillage_edge_id::Union{Nothing,Symbol} = nothing
    capacity::Any = nothing
    new_units::Any = nothing
    new_capacity::Any = nothing
    retired_units::Any = nothing
    retired_capacity::Any = nothing
    storage_level::Any = nothing
    storage_initial::Any = nothing
    storage_change::Any = nothing
    constraints::Dict{Any,Any} = Dict{Any,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct ProblemRefs
    nodes::Dict{Int,NodeRefs} = Dict{Int,NodeRefs}()
    unidirectional_edges::Dict{Int,UnidirectionalEdgeRefs} = Dict{Int,UnidirectionalEdgeRefs}()
    bidirectional_edges::Dict{Int,BidirectionalEdgeRefs} = Dict{Int,BidirectionalEdgeRefs}()
    unit_commitment_edges::Dict{Int,EdgeWithUCRefs} = Dict{Int,EdgeWithUCRefs}()
    transformations::Dict{Int,TransformationRefs} = Dict{Int,TransformationRefs}()
    storages::Dict{Int,StorageRefs} = Dict{Int,StorageRefs}()
    long_duration_storages::Dict{Int,StorageRefs} = Dict{Int,StorageRefs}()
    component_keys::Dict{Tuple{Symbol,Symbol},ComponentRefKey} = Dict{Tuple{Symbol,Symbol},ComponentRefKey}()
end

function ProblemRefs(spec)
    return ProblemRefs(
        nodes = Dict(idx => NodeRefs(component_index=idx) for idx in spec.node_indices),
        unidirectional_edges = Dict(
            idx => UnidirectionalEdgeRefs(edge=EdgeRefs(component_index=idx))
            for idx in spec.unidirectional_edge_indices
        ),
        bidirectional_edges = Dict(
            idx => BidirectionalEdgeRefs(edge=EdgeRefs(component_index=idx))
            for idx in spec.bidirectional_edge_indices
        ),
        unit_commitment_edges = Dict(
            idx => EdgeWithUCRefs(component_index=idx)
            for idx in spec.unit_commitment_edge_indices
        ),
        transformations = Dict(idx => TransformationRefs(component_index=idx) for idx in spec.transformation_indices),
        storages = Dict(idx => StorageRefs(component_index=idx) for idx in spec.storage_indices),
        long_duration_storages = Dict(idx => StorageRefs(component_index=idx) for idx in spec.long_duration_storage_indices),
    )
end

function component_ref_key(system, component)
    for field in (
        :nodes,
        :transformations,
        :storages,
        :long_duration_storages,
        :unidirectional_edges,
        :bidirectional_edges,
        :unit_commitment_edges,
    )
        components = getproperty(system, field)
        idx = findfirst(candidate -> candidate === component, components)
        if !isnothing(idx)
            return ComponentRefKey(field = field, index = idx)
        end
    end

    error("Component $(id(component)) is not present in the StaticSystem")
end

component_id_key(component) = (component_ref_field(component), id(component))

function set_component_ref_key!(refs::ProblemRefs, component, key::ComponentRefKey)
    refs.component_keys[component_id_key(component)] = key
    return nothing
end

function component_ref_key(refs::ProblemRefs, component)
    key = get(refs.component_keys, component_id_key(component), nothing)
    isnothing(key) && error("Component $(id(component)) is not included in this Problem")
    return key
end

function maybe_component_ref_key(system, component)
    isnothing(component) && return nothing
    return component_ref_key(system, component)
end

maybe_component_ref_key(system, key::ComponentRefKey) = key

function get_component_refs(refs::ProblemRefs, key::ComponentRefKey)
    return getproperty(refs, key.field)[key.index]
end

function get_component_refs(refs::ProblemRefs, component)
    return get_component_refs(refs, component_ref_key(refs, component))
end

function has_component_ref(refs::ProblemRefs, key::ComponentRefKey)
    return haskey(getproperty(refs, key.field), key.index)
end

function set_edge_endpoint_refs!(refs::Union{EdgeRefs,EdgeWithUCRefs}, system, edge)
    refs.start_vertex_ref = component_ref_key(system, start_vertex(edge))
    refs.end_vertex_ref = component_ref_key(system, end_vertex(edge))
    return nothing
end

function validate_edge_endpoint_refs!(refs::Union{EdgeRefs,EdgeWithUCRefs}, problem_refs::ProblemRefs, edge)
    has_component_ref(problem_refs, refs.start_vertex_ref) ||
        error("Start vertex $(id(start_vertex(edge))) for edge $(id(edge)) is not included in this Problem")
    has_component_ref(problem_refs, refs.end_vertex_ref) ||
        error("End vertex $(id(end_vertex(edge))) for edge $(id(edge)) is not included in this Problem")
    return nothing
end

function set_storage_edge_refs!(refs::StorageRefs, system, storage)
    refs.charge_edge_ref = maybe_component_ref_key(system, charge_edge(storage))
    refs.discharge_edge_ref = maybe_component_ref_key(system, discharge_edge(storage))
    refs.spillage_edge_ref = maybe_component_ref_key(system, spillage_edge(storage))
    refs.charge_edge_id = component_id(system, refs.charge_edge_ref)
    refs.discharge_edge_id = component_id(system, refs.discharge_edge_ref)
    refs.spillage_edge_id = component_id(system, refs.spillage_edge_ref)
    return nothing
end

component_id(system, key::Nothing) = nothing
component_id(system, key::ComponentRefKey) = id(getproperty(system, key.field)[key.index])

function validate_storage_edge_ref!(problem_refs::ProblemRefs, key, storage, edge_role::Symbol)
    isnothing(key) && return nothing
    has_component_ref(problem_refs, key) ||
        error("$(edge_role) edge for storage $(id(storage)) is not included in this Problem")
    return nothing
end

function validate_storage_edge_refs!(refs::StorageRefs, problem_refs::ProblemRefs, storage)
    validate_storage_edge_ref!(problem_refs, refs.charge_edge_ref, storage, :charge)
    validate_storage_edge_ref!(problem_refs, refs.discharge_edge_ref, storage, :discharge)
    validate_storage_edge_ref!(problem_refs, refs.spillage_edge_ref, storage, :spillage)
    return nothing
end

function ProblemRefs(system, spec)
    refs = ProblemRefs(spec)

    for (component_field, spec_field) in (
        (:nodes, :node_indices),
        (:transformations, :transformation_indices),
        (:storages, :storage_indices),
        (:long_duration_storages, :long_duration_storage_indices),
        (:unidirectional_edges, :unidirectional_edge_indices),
        (:bidirectional_edges, :bidirectional_edge_indices),
        (:unit_commitment_edges, :unit_commitment_edge_indices),
    )
        components = getproperty(system, component_field)
        for idx in getproperty(spec, spec_field)
            set_component_ref_key!(
                refs,
                components[idx],
                ComponentRefKey(field = component_field, index = idx),
            )
        end
    end

    for (component_field, spec_field) in (
        (:unidirectional_edges, :unidirectional_edge_indices),
        (:bidirectional_edges, :bidirectional_edge_indices),
        (:unit_commitment_edges, :unit_commitment_edge_indices),
    )
        edges = getproperty(system, component_field)
        refs_by_idx = getproperty(refs, component_field)

        for idx in getproperty(spec, spec_field)
            edge = edges[idx]
            edge_ref = edge_refs(refs_by_idx[idx])
            set_edge_endpoint_refs!(edge_ref, system, edge)
            validate_edge_endpoint_refs!(edge_ref, refs, edge)
        end
    end

    for (component_field, spec_field) in (
        (:storages, :storage_indices),
        (:long_duration_storages, :long_duration_storage_indices),
    )
        storages = getproperty(system, component_field)
        refs_by_idx = getproperty(refs, component_field)

        for idx in getproperty(spec, spec_field)
            storage = storages[idx]
            storage_refs = refs_by_idx[idx]
            set_storage_edge_refs!(storage_refs, system, storage)
            validate_storage_edge_refs!(storage_refs, refs, storage)
        end
    end

    return refs
end

edge_refs(refs::UnidirectionalEdgeRefs) = refs.edge
edge_refs(refs::BidirectionalEdgeRefs) = refs.edge
edge_refs(refs::EdgeWithUCRefs) = refs

start_vertex_ref(refs::UnidirectionalEdgeRefs) = refs.edge.start_vertex_ref
start_vertex_ref(refs::BidirectionalEdgeRefs) = refs.edge.start_vertex_ref
start_vertex_ref(refs::EdgeRefs) = refs.start_vertex_ref
start_vertex_ref(refs::EdgeWithUCRefs) = refs.start_vertex_ref
end_vertex_ref(refs::UnidirectionalEdgeRefs) = refs.edge.end_vertex_ref
end_vertex_ref(refs::BidirectionalEdgeRefs) = refs.edge.end_vertex_ref
end_vertex_ref(refs::EdgeRefs) = refs.end_vertex_ref
end_vertex_ref(refs::EdgeWithUCRefs) = refs.end_vertex_ref

capacity(refs::Union{EdgeRefs,EdgeWithUCRefs}) = refs.capacity
new_units(refs::Union{EdgeRefs,EdgeWithUCRefs}) = refs.new_units
new_capacity(refs::Union{EdgeRefs,EdgeWithUCRefs}) = refs.new_capacity
retired_units(refs::Union{EdgeRefs,EdgeWithUCRefs}) = refs.retired_units
retired_capacity(refs::Union{EdgeRefs,EdgeWithUCRefs}) = refs.retired_capacity
retrofitted_units(refs::Union{EdgeRefs,EdgeWithUCRefs}) = refs.retrofitted_units
retrofitted_capacity(refs::Union{EdgeRefs,EdgeWithUCRefs}) = refs.retrofitted_capacity
flow(refs::Union{EdgeRefs,EdgeWithUCRefs}) = refs.flow
flow(refs::Union{EdgeRefs,EdgeWithUCRefs}, t::Int64) = refs.flow[t]
ucommit(refs::EdgeWithUCRefs) = refs.ucommit
ucommit(refs::EdgeWithUCRefs, t::Int64) = refs.ucommit[t]
ustart(refs::EdgeWithUCRefs) = refs.ustart
ustart(refs::EdgeWithUCRefs, t::Int64) = refs.ustart[t]
ushut(refs::EdgeWithUCRefs) = refs.ushut
ushut(refs::EdgeWithUCRefs, t::Int64) = refs.ushut[t]

capacity(refs::StorageRefs) = refs.capacity
new_units(refs::StorageRefs) = refs.new_units
new_capacity(refs::StorageRefs) = refs.new_capacity
retired_units(refs::StorageRefs) = refs.retired_units
retired_capacity(refs::StorageRefs) = refs.retired_capacity
storage_level(refs::StorageRefs) = refs.storage_level
storage_level(refs::StorageRefs, t::Int64) = refs.storage_level[t]
storage_initial(refs::StorageRefs) = refs.storage_initial
storage_initial(refs::StorageRefs, r::Int64) = refs.storage_initial[r]
storage_change(refs::StorageRefs) = refs.storage_change
storage_change(refs::StorageRefs, w::Int64) = refs.storage_change[w]
charge_edge_id(refs::StorageRefs) = refs.charge_edge_id
discharge_edge_id(refs::StorageRefs) = refs.discharge_edge_id
spillage_edge_id(refs::StorageRefs) = refs.spillage_edge_id

charge_edge(refs::StorageRefs, problem::AbstractProblem) =
    edge_refs(get_component_refs(problem.refs, refs.charge_edge_ref))
discharge_edge(refs::StorageRefs, problem::AbstractProblem) =
    edge_refs(get_component_refs(problem.refs, refs.discharge_edge_ref))
spillage_edge(refs::StorageRefs, problem::AbstractProblem) =
    edge_refs(get_component_refs(problem.refs, refs.spillage_edge_ref))

get_balance(refs::Union{NodeRefs,TransformationRefs,StorageRefs}, i::Symbol) =
    refs.expressions[i]
get_balance(refs::Union{NodeRefs,TransformationRefs,StorageRefs}, i::Symbol, t::Int64) =
    get_balance(refs, i)[t]

parent_component(refs::NodeRefs, system) =
    system.nodes[refs.component_index]
parent_component(refs::UnidirectionalEdgeRefs, system) =
    system.unidirectional_edges[refs.edge.component_index]
parent_component(refs::BidirectionalEdgeRefs, system) =
    system.bidirectional_edges[refs.edge.component_index]
parent_component(refs::EdgeWithUCRefs, system) =
    system.unit_commitment_edges[refs.component_index]
parent_component(refs::TransformationRefs, system) =
    system.transformations[refs.component_index]
parent_component(refs::StorageRefs, system) =
    system.storages[refs.component_index]
parent_long_duration_storage(refs::StorageRefs, system) =
    system.long_duration_storages[refs.component_index]
