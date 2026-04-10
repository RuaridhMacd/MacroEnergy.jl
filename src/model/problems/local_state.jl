abstract type AbstractLocalState end

Base.@kwdef mutable struct NodeLocalState <: AbstractLocalState
    global_index::Int = 0
    local_time_indices::Vector{Int} = Int[]
    variables::Dict{Symbol,Any} = Dict{Symbol,Any}()
    constraints::Dict{Symbol,Any} = Dict{Symbol,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
    values::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct EdgeLocalState <: AbstractLocalState
    global_index::Int = 0
    local_time_indices::Vector{Int} = Int[]
    variables::Dict{Symbol,Any} = Dict{Symbol,Any}()
    constraints::Dict{Symbol,Any} = Dict{Symbol,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
    values::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct TransformationLocalState <: AbstractLocalState
    global_index::Int = 0
    local_time_indices::Vector{Int} = Int[]
    variables::Dict{Symbol,Any} = Dict{Symbol,Any}()
    constraints::Dict{Symbol,Any} = Dict{Symbol,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
    values::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct StorageLocalState <: AbstractLocalState
    global_index::Int = 0
    local_time_indices::Vector{Int} = Int[]
    variables::Dict{Symbol,Any} = Dict{Symbol,Any}()
    constraints::Dict{Symbol,Any} = Dict{Symbol,Any}()
    expressions::Dict{Symbol,Any} = Dict{Symbol,Any}()
    values::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

