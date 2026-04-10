Base.@kwdef struct ReassemblySlice
    problem_id::Symbol
    local_component_type::Symbol
    local_component_index::Int
    global_time_indices::Vector{Int} = Int[]
    local_time_indices::Vector{Int} = Int[]
end

Base.@kwdef struct ReassemblyMap
    nodes::Dict{Int,Vector{ReassemblySlice}} = Dict{Int,Vector{ReassemblySlice}}()
    unidirectional_edges::Dict{Int,Vector{ReassemblySlice}} = Dict{Int,Vector{ReassemblySlice}}()
    bidirectional_edges::Dict{Int,Vector{ReassemblySlice}} = Dict{Int,Vector{ReassemblySlice}}()
    unit_commitment_edges::Dict{Int,Vector{ReassemblySlice}} = Dict{Int,Vector{ReassemblySlice}}()
    transformations::Dict{Int,Vector{ReassemblySlice}} = Dict{Int,Vector{ReassemblySlice}}()
    storages::Dict{Int,Vector{ReassemblySlice}} = Dict{Int,Vector{ReassemblySlice}}()
    long_duration_storages::Dict{Int,Vector{ReassemblySlice}} = Dict{Int,Vector{ReassemblySlice}}()
end
