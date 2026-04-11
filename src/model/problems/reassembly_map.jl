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

function get_reassembly_bucket(reassembly_map::ReassemblyMap, component_group::Symbol)
    if component_group == :nodes
        return reassembly_map.nodes
    elseif component_group == :unidirectional_edges
        return reassembly_map.unidirectional_edges
    elseif component_group == :bidirectional_edges
        return reassembly_map.bidirectional_edges
    elseif component_group == :unit_commitment_edges
        return reassembly_map.unit_commitment_edges
    elseif component_group == :transformations
        return reassembly_map.transformations
    elseif component_group == :storages
        return reassembly_map.storages
    elseif component_group == :long_duration_storages
        return reassembly_map.long_duration_storages
    end
    error("Unknown reassembly component group $(component_group).")
end

function add_reassembly_slice!(
    reassembly_map::ReassemblyMap,
    component_group::Symbol,
    global_component_index::Int,
    slice::ReassemblySlice,
)
    bucket = get_reassembly_bucket(reassembly_map, component_group)
    push!(get!(bucket, global_component_index, ReassemblySlice[]), slice)
    return reassembly_map
end

function get_reassembly_slices(
    reassembly_map::ReassemblyMap,
    component_group::Symbol,
    global_component_index::Int,
)
    bucket = get_reassembly_bucket(reassembly_map, component_group)
    return get(bucket, global_component_index, ReassemblySlice[])
end

function get_first_reassembly_slice(
    reassembly_map::ReassemblyMap,
    component_group::Symbol,
    global_component_index::Int,
)
    slices = get_reassembly_slices(reassembly_map, component_group, global_component_index)
    return isempty(slices) ? nothing : first(slices)
end
