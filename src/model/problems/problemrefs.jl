Base.@kwdef struct ComponentRefKey
    period_index::Int
    field::Symbol
    index::Int
end

const PROBLEM_COMPONENT_FIELD_PAIRS = (
    (:nodes, :node_keys),
    (:transformations, :transformation_keys),
    (:storages, :storage_keys),
    (:long_duration_storages, :long_duration_storage_keys),
    (:unidirectional_edges, :unidirectional_edge_keys),
    (:bidirectional_edges, :bidirectional_edge_keys),
    (:unit_commitment_edges, :unit_commitment_edge_keys),
)

Base.@kwdef mutable struct NodeRefs
    component_key::ComponentRefKey
    non_served_demand::Any = nothing
    supply_flow::Any = nothing
    policy_budgeting_vars::Dict{Symbol,Any} = Dict{Symbol,Any}()
    policy_budgeting_constraints::Dict{DataType,Any} = Dict{DataType,Any}()
    policy_slack_vars::Dict{Symbol,Any} = Dict{Symbol,Any}()
    constraints::Dict{Any,Any} = Dict{Any,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct EdgeRefs
    component_key::ComponentRefKey
    start_vertex_ref::Union{Nothing,ComponentRefKey} = nothing
    end_vertex_ref::Union{Nothing,ComponentRefKey} = nothing
    capacity::Any = nothing
    new_units::Any = nothing
    new_capacity::Any = nothing
    retired_units::Any = nothing
    retired_capacity::Any = nothing
    retrofitted_units::Any = nothing
    retrofitted_capacity::Any = nothing
    existing_capacity::Any = nothing
    new_capacity_track::Dict{Int64,Any} = Dict{Int64,Any}()
    retired_capacity_track::Dict{Int64,Any} = Dict{Int64,Any}()
    retrofitted_capacity_track::Dict{Int64,Any} = Dict{Int64,Any}()
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
    component_key::ComponentRefKey
    start_vertex_ref::Union{Nothing,ComponentRefKey} = nothing
    end_vertex_ref::Union{Nothing,ComponentRefKey} = nothing
    capacity::Any = nothing
    new_units::Any = nothing
    new_capacity::Any = nothing
    retired_units::Any = nothing
    retired_capacity::Any = nothing
    retrofitted_units::Any = nothing
    retrofitted_capacity::Any = nothing
    existing_capacity::Any = nothing
    new_capacity_track::Dict{Int64,Any} = Dict{Int64,Any}()
    retired_capacity_track::Dict{Int64,Any} = Dict{Int64,Any}()
    retrofitted_capacity_track::Dict{Int64,Any} = Dict{Int64,Any}()
    flow::Any = nothing
    ucommit::Any = nothing
    ustart::Any = nothing
    ushut::Any = nothing
    constraints::Dict{Any,Any} = Dict{Any,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct TransformationRefs
    component_key::ComponentRefKey
    constraints::Dict{Any,Any} = Dict{Any,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct StorageRefs
    component_key::ComponentRefKey
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
    existing_capacity::Any = nothing
    new_capacity_track::Dict{Int64,Any} = Dict{Int64,Any}()
    retired_capacity_track::Dict{Int64,Any} = Dict{Int64,Any}()
    storage_level::Any = nothing
    storage_initial::Any = nothing
    storage_change::Any = nothing
    constraints::Dict{Any,Any} = Dict{Any,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct ProblemRefs
    nodes::Dict{ComponentRefKey,NodeRefs} = Dict{ComponentRefKey,NodeRefs}()
    unidirectional_edges::Dict{ComponentRefKey,UnidirectionalEdgeRefs} = Dict{ComponentRefKey,UnidirectionalEdgeRefs}()
    bidirectional_edges::Dict{ComponentRefKey,BidirectionalEdgeRefs} = Dict{ComponentRefKey,BidirectionalEdgeRefs}()
    unit_commitment_edges::Dict{ComponentRefKey,EdgeWithUCRefs} = Dict{ComponentRefKey,EdgeWithUCRefs}()
    transformations::Dict{ComponentRefKey,TransformationRefs} = Dict{ComponentRefKey,TransformationRefs}()
    storages::Dict{ComponentRefKey,StorageRefs} = Dict{ComponentRefKey,StorageRefs}()
    long_duration_storages::Dict{ComponentRefKey,StorageRefs} = Dict{ComponentRefKey,StorageRefs}()
    component_keys::Dict{Tuple{Int,Symbol,Symbol},ComponentRefKey} = Dict{Tuple{Int,Symbol,Symbol},ComponentRefKey}()
end

function ProblemRefs(spec)
    return ProblemRefs(
        nodes = Dict(key => NodeRefs(component_key = key) for key in spec.node_keys),
        unidirectional_edges = Dict(
            key => UnidirectionalEdgeRefs(edge = EdgeRefs(component_key = key))
            for key in spec.unidirectional_edge_keys
        ),
        bidirectional_edges = Dict(
            key => BidirectionalEdgeRefs(edge = EdgeRefs(component_key = key))
            for key in spec.bidirectional_edge_keys
        ),
        unit_commitment_edges = Dict(
            key => EdgeWithUCRefs(component_key = key)
            for key in spec.unit_commitment_edge_keys
        ),
        transformations = Dict(key => TransformationRefs(component_key = key) for key in spec.transformation_keys),
        storages = Dict(key => StorageRefs(component_key = key) for key in spec.storage_keys),
        long_duration_storages = Dict(key => StorageRefs(component_key = key) for key in spec.long_duration_storage_keys),
    )
end

component_key(refs::NodeRefs) = refs.component_key
component_key(refs::EdgeRefs) = refs.component_key
component_key(refs::UnidirectionalEdgeRefs) = refs.edge.component_key
component_key(refs::BidirectionalEdgeRefs) = refs.edge.component_key
component_key(refs::EdgeWithUCRefs) = refs.component_key
component_key(refs::TransformationRefs) = refs.component_key
component_key(refs::StorageRefs) = refs.component_key
component_index(refs) = component_key(refs).index

function component_ref_key(system, component)
    if system isa StaticSystem && !isempty(system.component_lookup)
        for (key, local_index) in system.component_lookup
            components = getproperty(system, key.field)
            if checkbounds(Bool, components, local_index) && components[local_index] === component
                return key
            end
        end
    end

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
            return ComponentRefKey(period_index = period_index(system), field = field, index = idx)
        end
    end

    error("Component $(id(component)) is not present in the StaticSystem for period $(period_index(system))")
end

function component_ref_key(systems::AbstractVector, component)
    for system in systems
        period_index(system) == period_index(component) || continue
        return component_ref_key(system, component)
    end
    error("Component $(id(component)) is not present in any StaticSystem for period $(period_index(component))")
end

component_id_key(component) = (period_index(component), component_ref_field(component), id(component))

function set_component_ref_key!(refs::ProblemRefs, component, key::ComponentRefKey)
    refs.component_keys[component_id_key(component)] = key
    return nothing
end

function component_ref_key(refs::ProblemRefs, component)
    key = get(refs.component_keys, component_id_key(component), nothing)
    isnothing(key) && error("Component $(id(component)) in period $(period_index(component)) is not included in this Problem")
    return key
end

function maybe_component_ref_key(system, component)
    isnothing(component) && return nothing
    return component_ref_key(system, component)
end

maybe_component_ref_key(system, key::ComponentRefKey) = key

function get_component_refs(refs::ProblemRefs, key::ComponentRefKey)
    return getproperty(refs, key.field)[key]
end

function get_component_refs(refs::ProblemRefs, component)
    return get_component_refs(refs, component_ref_key(refs, component))
end

function initialize_capacity_track_refs!(
    refs_track::Dict{Int64,Any},
    component_track::Dict{Int64,<:Any},
    current_period::Int,
)
    for (period, value) in component_track
        period == current_period && continue
        get!(refs_track, period, value)
    end
    return nothing
end

function initialize_capacity_refs!(
    component::Union{AbstractEdge,AbstractStorage},
    refs::Union{EdgeRefs,EdgeWithUCRefs,StorageRefs},
)
    current_period = period_index(component)

    if isnothing(refs.existing_capacity)
        refs.existing_capacity = existing_capacity(component)
    end

    initialize_capacity_track_refs!(refs.new_capacity_track, new_capacity_track(component), current_period)
    initialize_capacity_track_refs!(refs.retired_capacity_track, retired_capacity_track(component), current_period)

    if :retrofitted_capacity_track ∈ Base.fieldnames(typeof(refs)) &&
       :retrofitted_capacity_track ∈ Base.fieldnames(typeof(component))
        initialize_capacity_track_refs!(
            refs.retrofitted_capacity_track,
            retrofitted_capacity_track(component),
            current_period,
        )
    end

    return nothing
end

function has_component_ref(refs::ProblemRefs, key::ComponentRefKey)
    return haskey(getproperty(refs, key.field), key)
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
component_id(system, key::ComponentRefKey) = id(component(system, key))

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

function ProblemRefs(systems::AbstractVector, spec)
    refs = ProblemRefs(spec)

    for (component_field, spec_field) in PROBLEM_COMPONENT_FIELD_PAIRS
        for key in getproperty(spec, spec_field)
            set_component_ref_key!(refs, component(systems, key), key)
        end
    end

    for component_field in (:unidirectional_edges, :bidirectional_edges, :unit_commitment_edges)
        for (key, refs_for_key) in getproperty(refs, component_field)
            edge = component(systems, key)
            edge_ref = edge_refs(refs_for_key)
            set_edge_endpoint_refs!(edge_ref, systems, edge)
            validate_edge_endpoint_refs!(edge_ref, refs, edge)
        end
    end

    for component_field in (:storages, :long_duration_storages)
        for (key, storage_refs) in getproperty(refs, component_field)
            storage = component(systems, key)
            set_storage_edge_refs!(storage_refs, systems, storage)
            validate_storage_edge_refs!(storage_refs, refs, storage)
        end
    end

    return refs
end

ProblemRefs(system, spec) = ProblemRefs([system], spec)

edge_refs(refs::UnidirectionalEdgeRefs) = refs.edge
edge_refs(refs::BidirectionalEdgeRefs) = refs.edge
edge_refs(refs::EdgeWithUCRefs) = refs

capacity_refs(refs) = refs
capacity_refs(refs::UnidirectionalEdgeRefs) = refs.edge
capacity_refs(refs::BidirectionalEdgeRefs) = refs.edge

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
existing_capacity(refs::Union{EdgeRefs,EdgeWithUCRefs}) = refs.existing_capacity
new_capacity_track(refs::Union{EdgeRefs,EdgeWithUCRefs}) = refs.new_capacity_track
new_capacity_track(refs::Union{EdgeRefs,EdgeWithUCRefs}, s::Int64) =
    get(refs.new_capacity_track, s, 0.0)
retired_capacity_track(refs::Union{EdgeRefs,EdgeWithUCRefs}) = refs.retired_capacity_track
retired_capacity_track(refs::Union{EdgeRefs,EdgeWithUCRefs}, s::Int64) =
    get(refs.retired_capacity_track, s, 0.0)
retrofitted_capacity_track(refs::Union{EdgeRefs,EdgeWithUCRefs}) = refs.retrofitted_capacity_track
retrofitted_capacity_track(refs::Union{EdgeRefs,EdgeWithUCRefs}, s::Int64) =
    get(refs.retrofitted_capacity_track, s, 0.0)
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
existing_capacity(refs::StorageRefs) = refs.existing_capacity
new_capacity_track(refs::StorageRefs) = refs.new_capacity_track
new_capacity_track(refs::StorageRefs, s::Int64) =
    get(refs.new_capacity_track, s, 0.0)
retired_capacity_track(refs::StorageRefs) = refs.retired_capacity_track
retired_capacity_track(refs::StorageRefs, s::Int64) =
    get(refs.retired_capacity_track, s, 0.0)
retrofitted_capacity_track(refs::StorageRefs, s::Int64) = 0.0
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

parent_component(refs, system) =
    component(system, component_key(refs))
parent_component(refs, systems::AbstractVector) =
    component(systems, component_key(refs))
parent_long_duration_storage(refs::StorageRefs, system) =
    component(system, component_key(refs))
parent_long_duration_storage(refs::StorageRefs, systems::AbstractVector) =
    component(systems, component_key(refs))
