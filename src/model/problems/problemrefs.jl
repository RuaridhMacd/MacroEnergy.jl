Base.@kwdef mutable struct NodeRefs
    non_served_demand::Any = nothing
    supply_flow::Any = nothing
    policy_budgeting_vars::Dict{Symbol,Any} = Dict{Symbol,Any}()
    policy_budgeting_constraints::Dict{DataType,Any} = Dict{DataType,Any}()
    policy_slack_vars::Dict{DataType,Any} = Dict{DataType,Any}()
    constraints::Dict{DataType,Any} = Dict{DataType,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct EdgeRefs
    capacity::Any = nothing
    new_capacity::Any = nothing
    retired_capacity::Any = nothing
    retrofitted_capacity::Any = nothing
    flow::Any = nothing
    constraints::Dict{DataType,Any} = Dict{DataType,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct EdgeWithUCRefs
    edge::EdgeRefs = EdgeRefs()
    ucommit::Any = nothing
    ustart::Any = nothing
    ushut::Any = nothing
    constraints::Dict{DataType,Any} = Dict{DataType,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct TransformationRefs
    constraints::Dict{DataType,Any} = Dict{DataType,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct StorageRefs
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
    unidirectional_edges::Dict{Int,EdgeRefs} = Dict{Int,EdgeRefs}()
    bidirectional_edges::Dict{Int,EdgeRefs} = Dict{Int,EdgeRefs}()
    unit_commitment_edges::Dict{Int,EdgeWithUCRefs} = Dict{Int,EdgeWithUCRefs}()
    transformations::Dict{Int,TransformationRefs} = Dict{Int,TransformationRefs}()
    storages::Dict{Int,StorageRefs} = Dict{Int,StorageRefs}()
    long_duration_storages::Dict{Int,StorageRefs} = Dict{Int,StorageRefs}()
end

function ProblemRefs(spec::ProblemSpec)
    return ProblemRefs(
        nodes = Dict(idx => NodeRefs() for idx in spec.node_indices),
        unidirectional_edges = Dict(idx => EdgeRefs() for idx in spec.unidirectional_edge_indices),
        bidirectional_edges = Dict(idx => EdgeRefs() for idx in spec.bidirectional_edge_indices),
        unit_commitment_edges = Dict(idx => EdgeWithUCRefs() for idx in spec.unit_commitment_edge_indices),
        transformations = Dict(idx => TransformationRefs() for idx in spec.transformation_indices),
        storages = Dict(idx => StorageRefs() for idx in spec.storage_indices),
        long_duration_storages = Dict(idx => StorageRefs() for idx in spec.long_duration_storage_indices),
    )
end
