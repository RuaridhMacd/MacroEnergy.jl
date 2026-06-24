function all_subtypes(m::Module, type::Symbol)::Dict{Symbol,DataType}
    types = Dict{Symbol,DataType}()
    for subtype in subtypes(getfield(m, type))
        all_subtypes!(types, subtype)
    end
    return types
end

function all_subtypes!(types::Dict{Symbol,DataType}, type::DataType)
    types[typesymbol(type)] = type
    if !isempty(subtypes(type))
        for subtype in subtypes(type)
            all_subtypes!(types, subtype)
        end
    end
    return nothing
end

function all_subtypes!(types::Dict{Symbol,DataType}, type::UnionAll)
    return all_subtypes!(types, Base.unwrap_unionall(type))
end

function typesymbol(type::DataType)
    return Base.typename(type).name
end

function typesymbol(type::UnionAll)
    return Base.typename(type).name
end

function fieldnames(type::T) where {T<:Type{<:AbstractAsset}}
    return filter(x -> x != :id, Base.fieldnames(type))
end

###### ###### ###### ###### ###### ######
# Functions to check whether a path is relative or absolute, relative to a given directory
# Some of this might be unnecessary, as Julia does some of it automatically 
# to the current working directory

# However, I haven't tested it on all OS, and this lets us 
# set out own "root" directory

# We might need to swap the default behaviour to use the
# path relative to rel_dir
###### ###### ###### ###### ###### ######

function rel_or_abs_path(path::T, rel_dir::T = pwd())::String where {T<:AbstractString}
    if ispath(path)
        return path
    elseif ispath(joinpath(rel_dir, path))
        return joinpath(rel_dir, path)
    else
        return path
        # throw(ArgumentError("File $path not found"))
    end
end

recursive_merge(x::AbstractDict...) = merge(recursive_merge, x...)
recursive_merge(x::AbstractVector...) = cat(x...; dims = 1)
recursive_merge(x...) = x[end]

recursive_merge!(x::AbstractDict...) = merge!(recursive_merge!, x...)
recursive_merge!(x::AbstractVector...) = cat(x...; dims = 1)
recursive_merge!(x...) = x[end]

###### ###### ###### ###### ###### ######

function get_from(dict::T, keys::Vector{Symbol}, default) where T<:AbstractDict{Symbol, Any}
    for key in keys
        if haskey(dict, key)
            return get(dict, key, default)
        end
    end
    return default
end

function get_from(dicts::Vector{T}, key::Symbol, default) where T<:AbstractDict{Symbol, Any}
    for dict in dicts
        if haskey(dict, key)
            return get(dict, key, default)
        end
    end
    return default
end

function get_from(dicts::Vector{T}, keys::Vector{Symbol}, default) where T<:AbstractDict{Symbol, Any}
    for dict in dicts
        for key in keys
            if haskey(dict, key)
                return get(dict, key, default)
            end
        end
    end
    return default
end

function get_from(combos::Vector{Tuple{T, Symbol}}, default) where T<:AbstractDict{Symbol, Any}
    for (dict, key) in combos
        if haskey(dict, key)
            return get(dict, key, default)
        end
    end
    return default
end

function check_default(value, default)
    return value == default
end

function check_default(dict::AbstractDict, default)
    return all(values(dict) .== default)
end

function check_default(value, default::Missing)
    return ismissing(value)
end

function check_default(dict::AbstractDict, default::Missing)
    return all(ismissing.(values(dict)))
end

function get_from(combos::Vector{Tuple{T, Symbol}}, default, returnmissing::Bool) where T<:AbstractDict{Symbol, Any}
    for (dict, key) in combos
        if haskey(dict, key)
            value = get(dict, key, default)
            if !returnmissing && check_default(value, default)
                continue
            end
            return get(dict, key, default)
        end
    end
    return default
end

###### ###### ###### ###### ###### ######

function chained_get(d::Dict{Symbol,Any}, key_chain::Tuple{Vararg{Symbol}}, default=missing)
    if length(key_chain) == 1
        return get(d, key_chain[1], default)
    else
        if haskey(d, key_chain[1])
            return chained_get(d[key_chain[1]], key_chain[2:end], default)
        else
            return default
        end
    end
end

function chained_get(combos::Vector{Tuple{Dict{Symbol,Any}, Tuple{Vararg{Symbol}}}}, default=missing)
    for (dict, key_chain) in combos
        temp = chained_get(dict, key_chain, default)
        if temp != default
            return temp
        end
    end
    return default
end

###### ###### ###### ###### ###### ######

function replace_first_arg(expr::Expr, new_arg::Symbol)
    return Expr(expr.head, replace_first_arg(expr.args[1], new_arg), expr.args[2:end]...)
end

function replace_first_arg(expr::Symbol, new_arg::Symbol)
    return new_arg
end

macro setup_data(type, data, id)
    return esc(quote
        data = recursive_merge(clear_dict(default_data($type, $id, "full")), $data)
        defaults = default_data($type, $id, "full")
    end)
end

macro process_data(name, data, get_from_tuples)
    if isa(data, Symbol)
        defaults_name = :defaults
    elseif isa(data, Expr)
        defaults_name = replace_first_arg(data, :defaults) 
    end
    return esc(quote
        local loaded_data = Dict{Symbol,Any}(
            key => get_from($get_from_tuples, missing, false) for key in keys($data)
        )
        # Remove "missing" values to just get the loaded data
        remove_missing!(loaded_data)
        # Merge the loaded data into the original user-provided data
        # This should mean any simplified inputs are now in 
        # their fully-specified positions
        merge!($data, loaded_data)
        remove_missing!($data)
        # We can't recursive_merge! the dicts, as it will keep
        # both copies of some kinds of data.
        # But we do want to keep both copies of the constraints.
        # Therefore, we recursive_merge! the constraints, and then
        # merge the rest of the data.
        if haskey($data, :constraints)
            recursive_merge!($defaults_name[:constraints], $data[:constraints])
            $data[:constraints] = $defaults_name[:constraints]
        end
        merge!($defaults_name, $data)
        infer_edge_constraints!($defaults_name)
        $name = process_data($defaults_name)
    end)
end

function clear_dict(dict)
    for (key, value) in dict
        if isa(value, Dict{Symbol,Any})
            clear_dict(value)
        elseif isa(value, Dict{Symbol,Bool})
            # for k in keys(value)
            #     value[k] = missing
            # end
            dict[key] = missing
        else
            dict[key] = missing
        end
    end
    return dict
end

macro start_vertex(name, data, commodity, get_from_tuples)
    return esc(quote
        local vertex = get_from($get_from_tuples, missing, false)
        $data[:start_vertex] = vertex
        $name = find_node(system, Symbol(vertex), $commodity)
    end)
end

macro end_vertex(name, data, commodity, get_from_tuples)
    return esc(quote
        local vertex = get_from($get_from_tuples, missing, false)
        $data[:end_vertex] = vertex
        $name = find_node(system, Symbol(vertex), $commodity)
    end)
end

"""
    infer_edge_constraints!(edge_data::AbstractDict{Symbol,Any})

Infer constraint flags implied by edge input values. For example, setting a valid ramping fraction will enable the `RampingLimitConstraint` unless it has been explicitly set to `false`.

This mutates `edge_data` before constraint flags are converted into constraint objects.
Each inferred constraint should preserve an explicit `false` flag in `edge_data`.
"""
function infer_edge_constraints!(edge_data::AbstractDict{Symbol,Any})
    constraints = get!(edge_data, :constraints, Dict{Symbol,Bool}())

    is_unidirectional_edge = get(edge_data, :unidirectional, true)

    if has_ramping_input(edge_data) && get(constraints, :RampingLimitConstraint, true) != false
        constraints[:RampingLimitConstraint] = true
    end
    if has_minflow_input(edge_data) && is_unidirectional_edge && get(constraints, :MinFlowConstraint, true) != false
        constraints[:MinFlowConstraint] = true
    end
    if has_capacity_input(edge_data) && get(constraints, :CapacityConstraint, true) != false
        constraints[:CapacityConstraint] = true
    end
    if has_max_capacity_input(edge_data) && get(constraints, :MaxCapacityConstraint, true) != false
        constraints[:MaxCapacityConstraint] = true
    end
    if has_min_capacity_input(edge_data) && get(constraints, :MinCapacityConstraint, true) != false
        constraints[:MinCapacityConstraint] = true
    end
    if has_max_new_capacity_input(edge_data) && get(constraints, :MaxNewCapacityConstraint, true) != false
        constraints[:MaxNewCapacityConstraint] = true
    end

    is_uc_edge = get(edge_data, :uc, false)

    if is_uc_edge
        if has_minuptime_input(edge_data) && get(constraints, :MinUpTimeConstraint, true) != false
            constraints[:MinUpTimeConstraint] = true
        end
        if has_mindowntime_input(edge_data) && get(constraints, :MinDownTimeConstraint, true) != false
            constraints[:MinDownTimeConstraint] = true
        end
    end

    return nothing
end

"""
    has_ramping_input(edge_data::AbstractDict{Symbol,Any}) -> Bool

Return `true` when edge input data contains a binding ramping limit.

Ramping is considered binding when either `ramp_up_fraction` or
`ramp_down_fraction` is less than `1.0`. Missing ramping fractions are treated as
non-binding.
"""
function has_ramping_input(edge_data::AbstractDict{Symbol,Any})
    ramp_up_limit = get(edge_data, :ramp_up_fraction, 1.0)
    ramp_down_limit = get(edge_data, :ramp_down_fraction, 1.0)
    return (ramp_up_limit < 1.0) || (ramp_down_limit < 1.0)
end

"""
    has_minflow_input(edge_data::AbstractDict{Symbol,Any}) -> Bool

Return `true` when edge input data contains a binding minimum flow fraction.

A minimum flow is considered binding when `min_flow_fraction` is greater than `0.0`.
Missing minimum flow fractions are treated as non-binding.
"""
function has_minflow_input(edge_data::AbstractDict{Symbol,Any})
    min_flow_fraction = get(edge_data, :min_flow_fraction, 0.0)
    return min_flow_fraction > 0.0
end

"""
    has_capacity_input(edge_data::AbstractDict{Symbol,Any}) -> Bool

Return `true` when edge input data contains capacity information.
"""
function has_capacity_input(edge_data::AbstractDict{Symbol,Any})
    return get(edge_data, :has_capacity, false)
end

"""
    has_max_capacity_input(edge_data::AbstractDict{Symbol,Any}) -> Bool

Return `true` when edge input data contains a binding maximum capacity.

A maximum capacity is considered binding when `max_capacity` is less than `Inf`.
Missing maximum capacities are treated as non-binding.
"""
function has_max_capacity_input(edge_data::AbstractDict{Symbol,Any})
    max_capacity = get(edge_data, :max_capacity, Inf)
    if max_capacity == "Inf"
        return false
    end
    return max_capacity isa Real && max_capacity < Inf
end

"""
    has_min_capacity_input(edge_data::AbstractDict{Symbol,Any}) -> Bool

Return `true` when edge input data contains a binding minimum capacity.

A minimum capacity is considered binding when `min_capacity` is greater than `0.0`.
Missing minimum capacities are treated as non-binding.
"""
function has_min_capacity_input(edge_data::AbstractDict{Symbol,Any})
    min_capacity = get(edge_data, :min_capacity, 0.0)
    return min_capacity > 0.0
end

"""
    has_max_new_capacity_input(edge_data::AbstractDict{Symbol,Any}) -> Bool

Return `true` when edge input data contains a binding maximum new capacity.

A maximum new capacity is considered binding when `max_new_capacity` is less than `Inf`.
Missing maximum new capacities are treated as non-binding.
"""
function has_max_new_capacity_input(edge_data::AbstractDict{Symbol,Any})
    max_new_capacity = get(edge_data, :max_new_capacity, Inf)
    if max_new_capacity == "Inf"
        return false
    end
    return max_new_capacity isa Real && max_new_capacity < Inf
end

"""
    has_minuptime_input(edge_data::AbstractDict{Symbol,Any}) -> Bool

Return `true` when edge input data contains a binding minimum up time.

A minimum up time is considered binding when `min_up_time` is greater than `0.0`.
Missing minimum up times are treated as non-binding.
"""
function has_minuptime_input(edge_data::AbstractDict{Symbol,Any})
    min_up_time = get(edge_data, :min_up_time, 0.0)
    return min_up_time > 0.0
end

"""
    has_mindowntime_input(edge_data::AbstractDict{Symbol,Any}) -> Bool

Return `true` when edge input data contains a binding minimum down time.

A minimum down time is considered binding when `min_down_time` is greater than `0.0`.
Missing minimum down times are treated as non-binding.
"""
function has_mindowntime_input(edge_data::AbstractDict{Symbol,Any})
    min_down_time = get(edge_data, :min_down_time, 0.0)
    return min_down_time > 0.0
end
