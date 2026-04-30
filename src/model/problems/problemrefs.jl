Base.@kwdef mutable struct NodeRefs
    component_index::Int
    non_served_demand::Any = nothing
    supply_flow::Any = nothing
    policy_budgeting_vars::Dict{Symbol,Any} = Dict{Symbol,Any}()
    policy_budgeting_constraints::Dict{DataType,Any} = Dict{DataType,Any}()
    policy_slack_vars::Dict{DataType,Any} = Dict{DataType,Any}()
    constraints::Dict{DataType,Any} = Dict{DataType,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct EdgeRefs
    component_index::Int
    capacity::Any = nothing
    new_capacity::Any = nothing
    retired_capacity::Any = nothing
    retrofitted_capacity::Any = nothing
    flow::Any = nothing
    constraints::Dict{DataType,Any} = Dict{DataType,Any}()
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
    new_capacity::Any = nothing
    retired_capacity::Any = nothing
    retrofitted_capacity::Any = nothing
    flow::Any = nothing
    ucommit::Any = nothing
    ustart::Any = nothing
    ushut::Any = nothing
    constraints::Dict{DataType,Any} = Dict{DataType,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct TransformationRefs
    component_index::Int
    constraints::Dict{DataType,Any} = Dict{DataType,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct StorageRefs
    component_index::Int
    capacity::Any = nothing
    new_capacity::Any = nothing
    retired_capacity::Any = nothing
    storage_level::Any = nothing
    storage_initial::Any = nothing
    storage_change::Any = nothing
    constraints::Dict{DataType,Any} = Dict{DataType,Any}()
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

function ProblemRefs(spec::ProblemSpec)
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

parent_component(refs::NodeRefs, system::StaticSystem) =
    system.nodes[refs.component_index]
parent_component(refs::UnidirectionalEdgeRefs, system::StaticSystem) =
    system.unidirectional_edges[refs.edge.component_index]
parent_component(refs::BidirectionalEdgeRefs, system::StaticSystem) =
    system.bidirectional_edges[refs.edge.component_index]
parent_component(refs::EdgeWithUCRefs, system::StaticSystem) =
    system.unit_commitment_edges[refs.component_index]
parent_component(refs::TransformationRefs, system::StaticSystem) =
    system.transformations[refs.component_index]
parent_component(refs::StorageRefs, system::StaticSystem) =
    system.storages[refs.component_index]
parent_long_duration_storage(refs::StorageRefs, system::StaticSystem) =
    system.long_duration_storages[refs.component_index]
