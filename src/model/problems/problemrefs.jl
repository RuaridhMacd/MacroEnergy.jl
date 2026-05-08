Base.@kwdef mutable struct NodeRefs
    component_index::Int
    non_served_demand::Any = nothing
    supply_flow::Any = nothing
    policy_budgeting_vars::Dict{Symbol,Any} = Dict{Symbol,Any}()
    policy_budgeting_constraints::Dict{DataType,Any} = Dict{DataType,Any}()
    policy_slack_vars::Dict{DataType,Any} = Dict{DataType,Any}()
    constraints::Dict{Any,Any} = Dict{Any,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct EdgeRefs
    component_index::Int
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

edge_refs(refs::UnidirectionalEdgeRefs) = refs.edge
edge_refs(refs::BidirectionalEdgeRefs) = refs.edge
edge_refs(refs::EdgeWithUCRefs) = refs

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
