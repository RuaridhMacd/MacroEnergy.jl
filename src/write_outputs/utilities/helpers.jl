"""
Common helper functions for output generation.
"""

# Get the commodity type of a MacroObject
get_commodity_name(obj::AbstractEdge) = typesymbol(commodity_type(obj))
get_commodity_name(obj::Node) = typesymbol(commodity_type(obj))
get_commodity_name(obj::AbstractStorage) = typesymbol(commodity_type(obj))

# The commodity subtype is an identifier for the field names
# e.g., "capacity" for capacity variables, "flow" for flow variables, etc.
function get_commodity_subtype(f::Function)
    field_name = Symbol(f)
    if any(field_name .== (:capacity, :new_capacity, :retired_capacity, :existing_capacity, :retrofitted_capacity))
        return :capacity
    # elseif f == various cost # TODO: implement this
    #     return :cost
    else
        return field_name
    end
end

# Get the zone name/location of a vertex
get_zone_name(v::AbstractVertex) = ismissing(location(v)) ? id(v) : location(v)

# The zone name for an edge is derived from the locations of its connected vertices if not missing,
# otherwise the concatenation of the ids of its nodes:
# e.g., "elec_1_elec_2" for an edge connecting nodes "elec_1" and "elec_2" or 
# "elec_1" if connecting a node to storage/transformation
function get_zone_name(e::AbstractEdge)
    start_loc = location(e.start_vertex)
    end_loc = location(e.end_vertex)
    
    if !ismissing(start_loc) && !ismissing(end_loc)
        if start_loc == end_loc
            return start_loc
        else
            return Symbol("$(start_loc)_$(end_loc)")
        end
    elseif !ismissing(start_loc)
        return start_loc
    elseif !ismissing(end_loc)
        return end_loc
    end

    msg = "Edge $(id(e)) is not connected to any location because the nodes $(id(e.start_vertex)) and $(id(e.end_vertex)) are not connected to any location. \n"
    msg *= "If you want to specify the zone name for this edge, please add a location to the nodes $(id(e.start_vertex)) and $(id(e.end_vertex)) in the input data. \n"
    msg *= "The zone name in the output will be the concatenation of the ids of the nodes: $(id(e.start_vertex)) and $(id(e.end_vertex)). \n"
    msg *= "Please check the output data and adjust the zone name if necessary. \n"
    @warn msg
    
    region_name = join((id(n) for n in (e.start_vertex, e.end_vertex) if isa(n, Node)), "_")
    if isempty(region_name)
        region_name = join((id(n) for n in (e.start_vertex, e.end_vertex)), "_")
    end
    Symbol(region_name)
end

# New functions for flow outputs - get node_in and node_out
get_node_in(e::AbstractEdge) = id(e.start_vertex)
get_node_out(e::AbstractEdge) = id(e.end_vertex)

# The resource id is the id of the asset that the object belongs to
function get_resource_id(obj::T, asset_map::Dict{Symbol,Base.RefValue{<:AbstractAsset}}) where {T<:Union{AbstractEdge,AbstractStorage}}
    asset = asset_map[id(obj)]
    asset[].id
end
get_resource_id(obj::Node) = id(obj)

# The component id is the id of the object itself
get_component_id(obj::T) where {T<:Union{AbstractEdge,Node,AbstractStorage}} = Symbol("$(id(obj))")

# Get the type of an asset
function get_type(asset::Base.RefValue{<:AbstractAsset})
    asset = asset[]
    type_name = string(typesymbol(typeof(asset)))
    param_names = string.(typesymbol.(typeof(asset).parameters))
    if !isempty(param_names)
        return Symbol("\"$type_name{$(join(param_names, ","))}\"")
    else
        return Symbol(type_name)
    end   
end
# Get the type of a MacroObject
get_type(obj::T) where {T<:Union{AbstractEdge,Node,AbstractStorage}} = Symbol(typeof(obj))

# Get the unit of a MacroObject
get_unit(obj::AbstractEdge, f::Function) = unit(commodity_type(obj.timedata), f)    #TODO: check if this is correct
get_unit(obj::T, f::Function) where {T<:Union{Node,AbstractStorage}} = unit(commodity_type(obj), f)
