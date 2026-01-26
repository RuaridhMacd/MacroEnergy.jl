## Helper functions to extract optimal values of fields from MacroObjects ##
# The following functions are used to extract the values after the model has been solved
# from a list of MacroObjects (e.g., edges, and storage) and a list of fields (e.g., capacity, new_capacity, retired_capacity)
#   e.g.: get_optimal_vars(edges, (capacity, new_capacity, retired_capacity))
get_optimal_vars(objs::Vector{T}, field::Function, scaling::Float64=1.0, obj_asset_map::Dict{Symbol,Base.RefValue{<:AbstractAsset}}=Dict{Symbol,Base.RefValue{<:AbstractAsset}}()) where {T<:Union{AbstractEdge,Storage}} =
    get_optimal_vars(objs, (field,), scaling, obj_asset_map)
function get_optimal_vars(objs::Vector{T}, field_list::Tuple, scaling::Float64=1.0, obj_asset_map::Dict{Symbol,Base.RefValue{<:AbstractAsset}}=Dict{Symbol,Base.RefValue{<:AbstractAsset}}()) where {T<:Union{AbstractEdge,Storage}}
    # the obj_asset_map is used to map the asset component (e.g., natgas_1_natgas_edge, natgas_2_natgas_edge, natgas_1_elec_edge) to the actual asset id (e.g., natgas_1)
    total_rows = length(objs) * length(field_list)
    if isempty(obj_asset_map)
        return DataFrame(
            case_name = fill(missing, total_rows),
            commodity = [get_commodity_name(obj) for obj in objs for f in field_list],
            zone = [get_zone_name(obj) for obj in objs for f in field_list],
            resource_id = [get_component_id(obj) for obj in objs for f in field_list],
            component_id = [get_component_id(obj) for obj in objs for f in field_list],
            type = [get_type(obj) for obj in objs for f in field_list],
            variable = [Symbol(f) for obj in objs for f in field_list],
            year = fill(missing, total_rows),
            value = [Float64(value(f(obj))) * scaling for obj in objs for f in field_list]
        )
    else
        return DataFrame(
            case_name = fill(missing, total_rows),
            commodity = [get_commodity_name(obj) for obj in objs for f in field_list],
            zone = [get_zone_name(obj) for obj in objs for f in field_list],
            resource_id = [get_resource_id(obj, obj_asset_map) for obj in objs for f in field_list],
            component_id = [get_component_id(obj) for obj in objs for f in field_list],
            type = [get_type(obj_asset_map[id(obj)]) for obj in objs for f in field_list],
            variable = [Symbol(f) for obj in objs for f in field_list],
            year = fill(missing, total_rows),
            value = [Float64(value(f(obj))) * scaling for obj in objs for f in field_list]
        )
    end
end

## Helper functions to extract the optimal values of given fields from a list of MacroObjects at different time intervals ##
# e.g., get_optimal_vars_timeseries(edges, flow)

function get_optimal_vars_timeseries(
    objs::Vector{T},
    field_list::Tuple,
    scaling::Float64=1.0,
    obj_asset_map::Dict{Symbol,Base.RefValue{<:AbstractAsset}}=Dict{Symbol,Base.RefValue{<:AbstractAsset}}()
) where {T<:Union{AbstractEdge,AbstractStorage,Node,Location}}
    reduce(vcat, [get_optimal_vars_timeseries(o, field_list, scaling, obj_asset_map) for o in objs if !isa(o, Location)]) # filter out locations
end

function get_optimal_vars_timeseries(
    objs::Vector{T},
    f::Function,
    scaling::Float64=1.0,
    obj_asset_map::Dict{Symbol,Base.RefValue{<:AbstractAsset}}=Dict{Symbol,Base.RefValue{<:AbstractAsset}}()
) where {T<:Union{AbstractEdge,AbstractStorage,Node,Location}}
    reduce(vcat, [get_optimal_vars_timeseries(o, f, scaling, obj_asset_map) for o in objs if !isa(o, Location)])
end

function get_optimal_vars_timeseries(
    obj::T,
    field_list::Tuple,
    scaling::Float64=1.0,
    obj_asset_map::Dict{Symbol,Base.RefValue{<:AbstractAsset}}=Dict{Symbol,Base.RefValue{<:AbstractAsset}}()
) where {T<:Union{AbstractEdge,AbstractStorage,Node}}
    reduce(vcat, [get_optimal_vars_timeseries(obj, f, scaling, obj_asset_map) for f in field_list])
end

function get_optimal_vars_timeseries(
    obj::T,
    f::Function,
    scaling::Float64=1.0,
    obj_asset_map::Dict{Symbol,Base.RefValue{<:AbstractAsset}}=Dict{Symbol,Base.RefValue{<:AbstractAsset}}()
) where {T<:Union{AbstractEdge,AbstractStorage,Node}}
    time_axis = time_interval(obj)
    # check if the time series is piecewise linear approximation with segments
    has_segments = ndims(f(obj)) > 1 # a matrix (segments, time)
    num_segments = has_segments ? size(f(obj), 1) : 1
    total_rows = num_segments * length(time_axis)
    
    if isempty(obj_asset_map)
        return DataFrame(
            case_name = fill(missing, total_rows),
            commodity = Symbol[get_commodity_name(obj) for s in 1:num_segments for t in time_axis],
            zone = Symbol[get_zone_name(obj) for s in 1:num_segments for t in time_axis],
            resource_id = Symbol[get_component_id(obj) for s in 1:num_segments for t in time_axis],  # component id is same as resource id
            component_id = Symbol[get_component_id(obj) for s in 1:num_segments for t in time_axis],
            type = String[get_type(obj) for s in 1:num_segments for t in time_axis],
            variable = Symbol[Symbol(f) for s in 1:num_segments for t in time_axis],
            year = fill(missing, total_rows),
            segment = Int[s for s in 1:num_segments for t in time_axis],
            time = Int[t for s in 1:num_segments for t in time_axis],
            value = Float64[has_segments ? value(f(obj, s, t)) * scaling : value(f(obj, t)) * scaling for s in 1:num_segments for t in time_axis]
        )
    else
        return DataFrame(
            case_name = fill(missing, total_rows),
            commodity = Symbol[get_commodity_name(obj) for s in 1:num_segments for t in time_axis],
            zone = Symbol[get_zone_name(obj) for s in 1:num_segments for t in time_axis],
            resource_id = Symbol[isa(obj, Node) ? get_resource_id(obj) : get_resource_id(obj, obj_asset_map) for s in 1:num_segments for t in time_axis],
            component_id = Symbol[get_component_id(obj) for s in 1:num_segments for t in time_axis],
            type = String[isa(obj, Node) ? get_type(obj) : get_type(obj_asset_map[id(obj)]) for s in 1:num_segments for t in time_axis],
            variable = Symbol[Symbol(f) for s in 1:num_segments for t in time_axis],
            year = fill(missing, total_rows),
            segment = Int[s for s in 1:num_segments for t in time_axis],
            time = Int[t for s in 1:num_segments for t in time_axis],
            value = Float64[has_segments ? value(f(obj, s, t)) * scaling : value(f(obj, t)) * scaling for s in 1:num_segments for t in time_axis]
        )
    end
end
