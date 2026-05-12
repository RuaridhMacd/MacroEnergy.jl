mutable struct System <: AbstractSystem
    data_dirpath::String
    settings::NamedTuple
    commodities::Dict{Symbol,DataType}
    time_data::Dict{Symbol,TimeData}
    assets::Vector{AbstractAsset}
    locations::Vector{Union{Node, Location}}
    input_data::Vector{Dict{Symbol,Any}}
end

Base.@kwdef struct StaticSystem <: AbstractSystem
    period_index::Int = 1
    data_dirpath::String = ""
    settings::NamedTuple = NamedTuple()
    commodities::Dict{Symbol,DataType} = Dict{Symbol,DataType}()
    time_data::Dict{Symbol,TimeData} = Dict{Symbol,TimeData}()
    nodes::Vector{Node} = Node[]
    unidirectional_edges::Vector{UnidirectionalEdge} = UnidirectionalEdge[]
    bidirectional_edges::Vector{BidirectionalEdge} = BidirectionalEdge[]
    unit_commitment_edges::Vector{EdgeWithUC} = EdgeWithUC[]
    transformations::Vector{Transformation} = Transformation[]
    storages::Vector{Storage} = Storage[]
    long_duration_storages::Vector{LongDurationStorage} = LongDurationStorage[]
    assets::Vector{AbstractAsset} = AbstractAsset[]
    locations::Vector{Union{Node, Location}} = Union{Node, Location}[]
    component_lookup::Dict{ComponentRefKey,Int} = Dict{ComponentRefKey,Int}()
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

    static_system = StaticSystem(
        period_index = period_index(system),
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
        assets = copy(system.assets),
        locations = copy(system.locations),
    )
    set_storage_edge_keys!(static_system)
    return static_system
end

function component(system::StaticSystem, key::ComponentRefKey)
    key.period_index == period_index(system) ||
        error("Component key period $(key.period_index) does not match StaticSystem period $(period_index(system))")
    components = getproperty(system, key.field)
    local_index = get(system.component_lookup, key, key.index)
    return components[local_index]
end

function component(systems::AbstractVector{StaticSystem}, key::ComponentRefKey)
    system_idx = findfirst(system -> period_index(system) == key.period_index, systems)
    isnothing(system_idx) && error("No StaticSystem found for period $(key.period_index)")
    return component(systems[system_idx], key)
end

function storage_edge_key(system::StaticSystem, edge)
    isnothing(edge) && return nothing
    edge isa ComponentRefKey && return edge
    return component_ref_key(system, edge)
end

function set_storage_edge_keys!(storage::AbstractStorage, system::StaticSystem)
    storage.charge_edge = storage_edge_key(system, storage.charge_edge)
    storage.discharge_edge = storage_edge_key(system, storage.discharge_edge)
    storage.spillage_edge = storage_edge_key(system, storage.spillage_edge)
    return nothing
end

function set_storage_edge_keys!(system::StaticSystem)
    foreach(storage -> set_storage_edge_keys!(storage, system), system.storages)
    foreach(storage -> set_storage_edge_keys!(storage, system), system.long_duration_storages)
    return nothing
end

charge_edge(storage::AbstractStorage, system::StaticSystem) =
    isnothing(storage.charge_edge) ? nothing : component(system, storage.charge_edge)
discharge_edge(storage::AbstractStorage, system::StaticSystem) =
    isnothing(storage.discharge_edge) ? nothing : component(system, storage.discharge_edge)
spillage_edge(storage::AbstractStorage, system::StaticSystem) =
    isnothing(storage.spillage_edge) ? nothing : component(system, storage.spillage_edge)

"""
    asset_ids(system::System; source::String="assets")

Get the set of asset IDs from a system, either from loaded assets or input files.

# Arguments
- `system::System`: The system to get asset IDs from
- `source::String`: The source to get asset IDs from. Can be either:
  - `"assets"` (default): Get IDs from already loaded assets in the system
  - `"inputs"`: Get IDs from input files

# Returns
- `Set{AssetId}`: A set of asset IDs

# Examples
```julia
# Get IDs from loaded assets
ids = asset_ids(system)
```

# Notes
- If `source="assets"` and no assets are loaded, a warning is issued
- If an invalid source is provided, an error is thrown
"""
function asset_ids(system::System; source::String="assets")
    if source == "assets"
        if isempty(system.assets)
            @warn("System does not have any assets. Set source to 'inputs' to load assets from the input files.")
            return Set{AssetId}()
        end
        return map(x -> x.id, system.assets)
    elseif source == "inputs"
        return asset_ids_from_dir(system)
    else
        @error("Invalid source $source. Must be 'assets' or 'inputs'")
        return Set{AssetId}()
    end
end

function asset_ids(system::StaticSystem; source::String="assets")
    if source == "assets"
        if isempty(system.assets)
            @warn("StaticSystem does not have any assets.")
            return Set{AssetId}()
        end
        return map(x -> x.id, system.assets)
    elseif source == "inputs"
        error("StaticSystem does not store input files; use source=\"assets\".")
    else
        @error("Invalid source $source. Must be 'assets' or 'inputs'")
        return Set{AssetId}()
    end
end

"""
    location_ids(system::System)

Get a vector of the IDs of all locations in the system.

# Arguments
- `system`: A System object containing various locations

# Returns
- A vector of Symbols representing the IDs of all locations in the system

# Examples
```julia
ids = location_ids(system)
```
"""
location_ids(system::System) = map(x -> x.id, system.locations)
location_ids(system::StaticSystem) = map(x -> x.id, system.locations)

period_index(system::System) = first(values(system.time_data)).period_index;
period_index(system::StaticSystem) = system.period_index;

"""
    get_asset_types(system::System)

Get a vector of the types of all assets in the system.

# Arguments
- `system`: A System object containing various assets

# Returns
- A vector of DataTypes representing the type of each asset in the system

# Examples
```julia
asset_types = get_asset_types(system)
unique(asset_types)  # Get unique asset types in the system
```
"""
get_asset_types(system::System) = map(x -> typeof(x), system.assets)
get_asset_types(system::StaticSystem) = map(x -> typeof(x), system.assets)

function set_data_dirpath!(system::System, data_dirpath::String)
    system.data_dirpath = data_dirpath
end

function add!(system::System, asset::AbstractAsset)
    push!(system.assets, asset)
end

function add!(system::System, location::Node)
    push!(system.locations, location)
end

function empty_system(data_dirpath::String)
    @debug("Creating empty system, with data relative path set to $data_dirpath")
    return System(
        data_dirpath,
        NamedTuple(),
        Dict{Symbol,DataType}(),
        Dict{Symbol,TimeData}(),
        [],
        [],
        []
    )
end

"""
    get_asset_by_id(system::System, id::Symbol)

Find an asset in the system by its ID.

# Arguments
- `system`: A System object containing various assets
- `id`: Symbol representing the ID of the asset to find

# Returns
- The asset object if found
- `nothing` if no asset with the given ID exists

# Examples
```julia
# Find a battery asset
battery = get_asset_by_id(system, :battery_SE)

# Find a thermal power plant
thermal_plant = get_asset_by_id(system, :natural_gas_SE)
```
"""
function get_asset_by_id(system::System, id::Symbol)
    for asset in system.assets
        if asset.id == id
            return asset
        end
    end
    return nothing
end

function get_input_data_by_id(system::System, id::Symbol)
    for input_data in system.input_data
        if input_data[:id] == id
            return input_data
        end
    end
    return nothing
end

function find_locations(system::System, id::Symbol)
    for location in system.locations
        if location.id == id
            return location
        end
    end
    return nothing
end

"""
    find_node(nodes_list::Vector{Union{Node, Location}}, id::Symbol, commodity::Union{Missing,DataType}=missing)

Search for a node with the specified `id` and optional `commodity` type in a list of nodes and locations.

# Arguments
- `nodes_list`: Vector of nodes and locations to search through
- `id`: Symbol representing the ID of the node to find
- `commodity`: Optional DataType specifying the commodity type of the node (default: missing)

# Returns
- The found node if it exists
- Throws an error if no matching node is found

# Examples
```julia
# Find a node by ID only
node = find_node(system.locations, :co2_sink)
```
"""
function find_node(nodes_list::Vector{Union{Node, Location}}, id::Symbol, commodity::Union{Missing,DataType}=missing)
    @debug "Finding node $id of commodity $commodity"
    for node in nodes_list
        # Please reformat the code below
        candidate = find_node(node, id, commodity)
        if candidate !== nothing
            return candidate
        end
    end
    return nothing
end

function find_node(system::System, id::Symbol, commodity::Union{Missing,DataType}=missing)
    @debug "Finding node $id of commodity $commodity"
    candidate = find_node(system.locations, id, commodity)
    if candidate !== nothing
        return candidate
    elseif system.settings.AutoCreateNodes
        id = Symbol(rand(Int16))
        @debug "Creating new $commodity node with id: $id"
        new_node = Node{commodity}(; 
            id = id,
            timedata = system.time_data[Symbol(commodity)]
        )
        push!(system.locations, new_node)
        return new_node
    end
    error("Node $id not found")
    return nothing
end

function find_node(node::Node, id::Symbol, commodity::Union{Missing,DataType}=missing)
    if node.id == id
        return node
    end
    return nothing
end

function find_node(location::Location, id::Symbol, commodity::Union{Missing,DataType}=missing)
    # If commodity is missing, skip
    if commodity === missing
        return nothing
    end
    if location.id == id
        commodity_symbol = typesymbol(commodity)
        if commodity_symbol in location.commodities
            @debug "Found $commodity node called $id"
            # If the location has a node of the commodity we need, return it
            return location.nodes[commodity_symbol]
        elseif location.system.settings.AutoCreateNodes
            # Otherwise, create a new node of the commodity and return it
            @debug "Making $commodity node called $id"
            new_node = Node{commodity}(;
                id = id,
                timedata = location.system.time_data[commodity_symbol]
            )
            add_node!(location, new_node)
            push!(location.system.locations, new_node)
            return new_node
        else
            @warn("Node $id not found\nNot creating a new Node as AutoCreateNodes = false")
        end
    end
    return nothing
end

# The following functions are used to extract all the assets of a given type from a System or a Vector of Assets
"""
    get_assets_sametype(system::System, asset_type::T) where T<:Type{<:AbstractAsset}

Get all assets of a specific type from the system.

# Arguments
- `system`: A System object containing various assets
- `asset_type`: The type of assets to retrieve (must be a subtype of AbstractAsset)

# Returns
- A vector of assets of the specified type

# Examples
```julia
# Get all battery assets
batteries = get_assets_sametype(system, Battery)
battery = batteries[1]  # first battery in the list

# Get all natural gas thermal power plants
thermal_plants = get_assets_sametype(system, ThermalPower{NaturalGas})
```
"""
get_assets_sametype(system::System, asset_type::T) where T<:Type{<:AbstractAsset} = get_assets_sametype(system.assets, asset_type)
get_assets_sametype(system::StaticSystem, asset_type::T) where T<:Type{<:AbstractAsset} =
    get_assets_sametype(system.assets, asset_type)

# Function to extract all the nodes, edges, storages, and transformations from a system
# If return_ids_map=True, a `Dict` is also returned mapping edge ids to the corresponding asset objects.
get_locations(system::System) = system.locations
get_nodes(system::System) = Node[node for node in system.locations if isa(node, Node)]
get_edges(system::System; return_ids_map::Bool=false) = return_ids_map ? get_macro_objs_with_map(system, AbstractEdge) : get_macro_objs(system, AbstractEdge)
get_storages(system::System; return_ids_map::Bool=false) = return_ids_map ? get_macro_objs_with_map(system, AbstractStorage) : get_macro_objs(system, AbstractStorage)
get_transformations(system::System; return_ids_map::Bool=false) = return_ids_map ? get_macro_objs_with_map(system, Transformation) : get_macro_objs(system, Transformation)

get_locations(system::StaticSystem) = system.locations
get_nodes(system::StaticSystem) = system.nodes

function get_edges(system::StaticSystem; return_ids_map::Bool=false)
    edges = AbstractEdge[
        system.unidirectional_edges...,
        system.bidirectional_edges...,
        system.unit_commitment_edges...,
    ]
    return return_ids_map ? (edges, get_edge_asset_map(system)) : edges
end

function get_storages(system::StaticSystem; return_ids_map::Bool=false)
    storages = AbstractStorage[
        system.storages...,
        system.long_duration_storages...,
    ]
    return return_ids_map ? (storages, get_storage_asset_map(system)) : storages
end

function get_transformations(system::StaticSystem; return_ids_map::Bool=false)
    return return_ids_map ? (system.transformations, get_transformation_asset_map(system)) : system.transformations
end

function get_edge_asset_map(system::StaticSystem)
    _, edge_asset_map = get_macro_objs_with_map(system.assets, AbstractEdge)
    return edge_asset_map
end

function get_storage_asset_map(system::StaticSystem)
    _, storage_asset_map = get_macro_objs_with_map(system.assets, AbstractStorage)
    return storage_asset_map
end

function get_transformation_asset_map(system::StaticSystem)
    _, transformation_asset_map = get_macro_objs_with_map(system.assets, Transformation)
    return transformation_asset_map
end

# Function to extract the edges with capacity variables from a system.
# If return_ids_map=True, a `Dict` is also returned mapping edge ids to the corresponding asset objects.  
function edges_with_capacity_variables(system::System; return_ids_map::Bool=false)
    if return_ids_map
        edges, edge_asset_map = get_edges(system, return_ids_map=true)
        edges_with_capacity = edges_with_capacity_variables(edges)
        edges_with_capacity_asset_map = filter(edge -> edge[1] in id.(edges_with_capacity), edge_asset_map)
        return edges_with_capacity, edges_with_capacity_asset_map
    else
        return edges_with_capacity_variables(system.assets)
    end
end

function edges_with_capacity_variables(system::StaticSystem; return_ids_map::Bool=false)
    if return_ids_map
        edges, edge_asset_map = get_edges(system, return_ids_map=true)
        edges_with_capacity = edges_with_capacity_variables(edges)
        edges_with_capacity_asset_map = filter(edge -> edge[1] in id.(edges_with_capacity), edge_asset_map)
        return edges_with_capacity, edges_with_capacity_asset_map
    else
        return edges_with_capacity_variables(get_edges(system))
    end
end

# Function to extract the storages with capacity variables from a system.
# If return_ids_map=True, a `Dict` is also returned mapping edge ids to the corresponding asset objects.  
function storages_with_capacity_variables(system::System; return_ids_map::Bool=false)
    if return_ids_map
        ### Note: we do not need to filter storages as every storage has capacity variables
        storages_with_capacity, storages_with_capacity_asset_map = get_storages(system, return_ids_map=true)
        return storages_with_capacity, storages_with_capacity_asset_map
    else
        return storages_with_capacity_variables(system.assets)
    end
end

function storages_with_capacity_variables(system::StaticSystem; return_ids_map::Bool=false)
    if return_ids_map
        return get_storages(system, return_ids_map=true)
    else
        return storages_with_capacity_variables(get_storages(system))
    end
end

function asset_ids_from_file(asset_file::AbstractString, ids::Set{AssetId}=Set{AssetId}())
    if !isfile(asset_file)
        @error("Asset file $asset_file not found")
        return Set{AssetId}()
    end
    asset_data = load_inputs(asset_file)
    for asset_type in values(asset_data)
        ids = asset_ids_from_file(asset_type, ids)
    end
    return ids
end

function asset_ids_from_file(asset_type::Dict{Symbol,Any}, ids::Set{AssetId}=Set{AssetId}())
    if isa(asset_type[:instance_data], Dict{Symbol,Any})
        asset_type[:instance_data] = [asset_type[:instance_data]]
    end
    for asset in asset_type[:instance_data]
        if !haskey(asset, :id)
            @warn("Asset $(asset_type[:type]) does not have an id. Skipping...")
            continue
        end
        asset_id = AssetId(asset[:id])
        if asset_id ∈ ids
            @warn("Duplicate asset id $asset_id. Skipping...")
            continue
        end
        push!(ids, asset_id)
    end
    return ids
end

function asset_ids_from_file(data::AbstractVector, ids::Set{AssetId}=Set{AssetId}())
    for asset_type in data
        ids = asset_ids_from_file(asset_type, ids)
    end
    return ids
end

function asset_ids_from_dir(dirpath::AbstractString, ids::Set{AssetId}=Set{AssetId}())
    for (root, dirs, files) in Base.Filesystem.walkdir(dirpath)
        for file in files
            if endswith(file, ".json") || endswith(file, ".csv")
                ids = asset_ids_from_file(joinpath(root, file), ids)
            end
        end
    end
    return ids
end

function asset_ids_from_dir(system::System, ids::Set{AssetId}=Set{AssetId}())
    system_data = load_system_data(joinpath(system.data_dirpath, "system_data.json"); lazy_load = true)
    assets_dir = joinpath(system.data_dirpath, system_data[:assets][:path])
    if !isdir(assets_dir)
        @error("Assets directory $assets_dir not found")
        return Set{AssetId}()
    end
    return asset_ids_from_dir(assets_dir, ids)
end

function unique_id(base_id::AssetId, existing_ids::Union{Set{AssetId},AbstractVector{AssetId}})
    id = base_id
    i = 1
    while id ∈ existing_ids
        id = AssetId(string(base_id, "_", i))
        i += 1
    end
    return id
end
