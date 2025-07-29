function find_connected_groups(edges::Vector{AbstractEdge}, vertices::Vector{AbstractVertex})
    vertex_ids = id.(vertices)

    vertex_id_to_index = Dict(v=>i for (i,v) in enumerate(vertex_ids))
    N = length(vertex_ids)

    ds = IntDisjointSets(N)
    for e in edges
        ui = vertex_id_to_index[e.start_vertex.id]
        vi = vertex_id_to_index[e.end_vertex.id]
        union!(ds, ui, vi)
    end

    groups = Dict{Int, NamedTuple{(:vertices,:edges),Tuple{Vector{Int},Vector{Int}}}}()

    # Collect vertex indices
    for i in 1:N
        r = find_root(ds, i)
        if !haskey(groups, r)
            groups[r] = (vertices = Int[], edges = Int[])
        end
        push!(groups[r].vertices, i)
    end

    # Collect edge indices
    for (j, e) in enumerate(edges)
        ui = vertex_id_to_index[e.start_vertex.id]
        vi = vertex_id_to_index[e.end_vertex.id]
        ru = find_root(ds, ui)
        rv = find_root(ds, vi)
        # only add if both ends really lie in the same component
        if ru == rv
            push!(groups[ru].edges, j)
        end
    end

    # Rename the keys to be indexed 1:length(groups)
    ordered_groups = Dict{Int,NamedTuple{(:vertices,:edges),Tuple{Vector{Int},Vector{Int}}}}(
        idx => group for (idx, group) in enumerate(values(groups))
    )

    # Convert vertex and edge indices to actual objects
    comps = Dict{Int, NamedTuple{(:vertices,:edges),Tuple{Vector{AbstractVertex},Vector{AbstractEdge}}}}(
        idx => (
            vertices = [vertices[i] for i in group.vertices],
            edges = [edges[i] for i in group.edges]
        ) for (idx, group) in ordered_groups
    )

    return groups, comps
end

function find_connected_groups(system::AbstractSystem)
    edges = get_edges(system)
    vertices = get_vertices(system)
    _, comps = find_connected_groups(edges, vertices)
    return comps
end
