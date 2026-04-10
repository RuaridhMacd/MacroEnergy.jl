Base.@kwdef struct AssetView
    id::AssetId
    node_indices::Vector{Int} = Int[]
    unidirectional_edge_indices::Vector{Int} = Int[]
    bidirectional_edge_indices::Vector{Int} = Int[]
    unit_commitment_edge_indices::Vector{Int} = Int[]
    transformation_indices::Vector{Int} = Int[]
    storage_indices::Vector{Int} = Int[]
    long_duration_storage_indices::Vector{Int} = Int[]
end

Base.@kwdef struct LocationView
    id::Symbol
    node_indices::Vector{Int} = Int[]
end

Base.@kwdef struct StaticSystem
    data_dirpath::String = ""
    settings::Union{NamedTuple,Nothing} = nothing
    commodities::Dict{Symbol,DataType} = Dict{Symbol,DataType}()
    time_data::Dict{Symbol,TimeData} = Dict{Symbol,TimeData}()
    nodes::Vector{Node} = Node[]
    unidirectional_edges::Vector{UnidirectionalEdge} = UnidirectionalEdge[]
    bidirectional_edges::Vector{BidirectionalEdge} = BidirectionalEdge[]
    unit_commitment_edges::Vector{EdgeWithUC} = EdgeWithUC[]
    transformations::Vector{Transformation} = Transformation[]
    storages::Vector{Storage} = Storage[]
    long_duration_storages::Vector{LongDurationStorage} = LongDurationStorage[]
    assets::Vector{AssetView} = AssetView[]
    locations::Vector{LocationView} = LocationView[]
end

function StaticSystem(system::System)
    nodes = get_nodes(system)
    edges = get_edges(system)
    transformations = get_transformations(system)
    storages_all = get_storages(system)

    unidirectional_edges = UnidirectionalEdge[
        edge for edge in edges if edge isa UnidirectionalEdge
    ]
    bidirectional_edges = BidirectionalEdge[
        edge for edge in edges if edge isa BidirectionalEdge
    ]
    unit_commitment_edges = EdgeWithUC[
        edge for edge in edges if edge isa EdgeWithUC
    ]
    storages = Storage[
        storage for storage in storages_all if storage isa Storage
    ]
    long_duration_storages = LongDurationStorage[
        storage for storage in storages_all if storage isa LongDurationStorage
    ]

    node_index = Dict(id(node) => idx for (idx, node) in pairs(nodes))
    unidirectional_edge_index = Dict(
        id(edge) => idx for (idx, edge) in pairs(unidirectional_edges)
    )
    bidirectional_edge_index = Dict(
        id(edge) => idx for (idx, edge) in pairs(bidirectional_edges)
    )
    unit_commitment_edge_index = Dict(
        id(edge) => idx for (idx, edge) in pairs(unit_commitment_edges)
    )
    transformation_index = Dict(
        id(transformation) => idx for (idx, transformation) in pairs(transformations)
    )
    storage_index = Dict(id(storage) => idx for (idx, storage) in pairs(storages))
    long_duration_storage_index = Dict(
        id(storage) => idx for (idx, storage) in pairs(long_duration_storages)
    )

    asset_views = AssetView[
        build_asset_view(
            asset,
            node_index,
            unidirectional_edge_index,
            bidirectional_edge_index,
            unit_commitment_edge_index,
            transformation_index,
            storage_index,
            long_duration_storage_index,
        ) for asset in system.assets
    ]

    location_views = build_location_views(system, node_index)

    return StaticSystem(
        data_dirpath = system.data_dirpath,
        settings = system.settings,
        commodities = copy(system.commodities),
        time_data = copy(system.time_data),
        nodes = nodes,
        unidirectional_edges = unidirectional_edges,
        bidirectional_edges = bidirectional_edges,
        unit_commitment_edges = unit_commitment_edges,
        transformations = transformations,
        storages = storages,
        long_duration_storages = long_duration_storages,
        assets = asset_views,
        locations = location_views,
    )
end

function build_asset_view(
    asset::AbstractAsset,
    node_index::Dict{Symbol,Int},
    unidirectional_edge_index::Dict{Symbol,Int},
    bidirectional_edge_index::Dict{Symbol,Int},
    unit_commitment_edge_index::Dict{Symbol,Int},
    transformation_index::Dict{Symbol,Int},
    storage_index::Dict{Symbol,Int},
    long_duration_storage_index::Dict{Symbol,Int},
)
    asset_nodes = Node[]
    asset_unidirectional_edges = UnidirectionalEdge[]
    asset_bidirectional_edges = BidirectionalEdge[]
    asset_unit_commitment_edges = EdgeWithUC[]
    asset_transformations = Transformation[]
    asset_storages = Storage[]
    asset_long_duration_storages = LongDurationStorage[]

    for field_name in propertynames(asset)
        component = getproperty(asset, field_name)
        if component isa Node
            push!(asset_nodes, component)
        elseif component isa UnidirectionalEdge
            push!(asset_unidirectional_edges, component)
        elseif component isa BidirectionalEdge
            push!(asset_bidirectional_edges, component)
        elseif component isa EdgeWithUC
            push!(asset_unit_commitment_edges, component)
        elseif component isa Transformation
            push!(asset_transformations, component)
        elseif component isa Storage
            push!(asset_storages, component)
        elseif component isa LongDurationStorage
            push!(asset_long_duration_storages, component)
        end
    end

    return AssetView(
        id = id(asset),
        node_indices = [node_index[id(node)] for node in asset_nodes if haskey(node_index, id(node))],
        unidirectional_edge_indices = [
            unidirectional_edge_index[id(edge)] for edge in asset_unidirectional_edges
            if haskey(unidirectional_edge_index, id(edge))
        ],
        bidirectional_edge_indices = [
            bidirectional_edge_index[id(edge)] for edge in asset_bidirectional_edges
            if haskey(bidirectional_edge_index, id(edge))
        ],
        unit_commitment_edge_indices = [
            unit_commitment_edge_index[id(edge)] for edge in asset_unit_commitment_edges
            if haskey(unit_commitment_edge_index, id(edge))
        ],
        transformation_indices = [
            transformation_index[id(transformation)] for transformation in asset_transformations
            if haskey(transformation_index, id(transformation))
        ],
        storage_indices = [
            storage_index[id(storage)] for storage in asset_storages
            if haskey(storage_index, id(storage))
        ],
        long_duration_storage_indices = [
            long_duration_storage_index[id(storage)] for storage in asset_long_duration_storages
            if haskey(long_duration_storage_index, id(storage))
        ],
    )
end

function build_location_views(system::System, node_index::Dict{Symbol,Int})
    location_views = LocationView[]
    for location in get_locations(system)
        if location isa Location
            push!(
                location_views,
                LocationView(
                    id = location.id,
                    node_indices = [
                        node_index[id(node)] for node in values(location.nodes)
                        if haskey(node_index, id(node))
                    ],
                ),
            )
        end
    end
    return location_views
end
