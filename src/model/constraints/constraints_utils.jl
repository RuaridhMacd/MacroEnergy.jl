constraint_value(c::AbstractTypeConstraint) = c.constraint_value;
constraint_dual(c::AbstractTypeConstraint) = c.constraint_dual;
constraint_ref(c::AbstractTypeConstraint) = c.constraint_ref;

"""
    configure_constraint!(ct::AbstractTypeConstraint, cfg)

Store inline configuration `cfg` on a constraint instance. `cfg` is the value parsed from a
`constraints` block when it is an object rather than `true` (see `check_and_convert_constraints!`).
Only constraint types that support inline configuration define a method; the generic fallback errors.
"""
configure_constraint!(ct::AbstractTypeConstraint, cfg) =
    error("Constraint $(typeof(ct)) does not support inline configuration")

"""
    AbstractConstraintConfig

Abstract supertype for typed, inline constraint configuration payloads. Constraint types that
support object values in an input `constraints` block define a concrete subtype.
"""
abstract type AbstractConstraintConfig end

"""
    AbstractGroupedConstraintConfig <: AbstractConstraintConfig

Abstract supertype for configurations that define one or more asset groups. Each group selects
assets and constrains a capacity-like quantity on a named edge field.
"""
abstract type AbstractGroupedConstraintConfig <: AbstractConstraintConfig end

"""
    GroupConfig(selector, edge, value)

One asset group in a grouped constraint configuration.

- `selector`: asset-type selector, such as `:VRE`, `Symbol("ThermalPower{NaturalGas}")`, or
  `Symbol("VRE*")`.
- `edge`: field name of the constrained edge on every selected asset.
- `value`: upper or lower bound, depending on the enclosing constraint.
"""
struct GroupConfig
    selector::Symbol
    edge::Symbol
    value::Float64
end

constraint_groups(config::AbstractGroupedConstraintConfig) = config.groups
group_selector(group) = group.selector
group_edge(group) = group.edge
group_value(group) = group.value

requires_constraint_config(::AbstractTypeConstraint) = false
required_constraint_config_type(::AbstractTypeConstraint) = nothing
constraint_config_is_missing(::AbstractTypeConstraint) = false

"""
    validate_required_constraint_configs!(constraints, scope)

Ensure constraints attached at `scope` have the configuration payload required by that scope.
Component-level constraints remain compatible with their legacy Boolean form; grouped constraints
at system and location scope require a typed object payload.
"""
function validate_required_constraint_configs!(
    constraints::AbstractVector{<:AbstractTypeConstraint},
    scope::AbstractString,
)
    for constraint in constraints
        requires_constraint_config(constraint) || continue
        constraint_config_is_missing(constraint) || continue
        config_type = required_constraint_config_type(constraint)
        constraint_name = nameof(typeof(constraint))
        throw(ArgumentError(
            "$constraint_name at $scope requires a $(config_type) configuration object. " *
            "In input JSON, provide an object payload for `$constraint_name` rather than `true`.",
        ))
    end
    return nothing
end

"""
    parse_grouped_constraint_config(raw, group_type, config_type, constraint_name)

Parse the object payload used by a grouped capacity constraint into its concrete, typed config.
Each payload entry maps an asset selector to an object with exactly `edge` and `value` keys.
`group_type` must accept `(selector::Symbol, edge::Symbol, value::Float64)` and `config_type`
must accept the resulting vector of groups. The current grouped capacity constraints all use the
shared `GroupConfig` entry type while retaining separate outer configuration schemas.
"""
function parse_grouped_constraint_config(
    raw::AbstractDict,
    ::Type{G},
    ::Type{C},
    constraint_name::String,
) where {G,C<:AbstractGroupedConstraintConfig}
    groups = G[]
    selectors = Set{Symbol}()

    for (raw_selector, raw_group) in raw
        raw_selector isa Union{Symbol,AbstractString} || throw(ArgumentError(
            "$constraint_name selector `$raw_selector` must be a string.",
        ))
        selector = Symbol(raw_selector)
        selector in selectors && throw(ArgumentError(
            "$constraint_name has a duplicate selector `$selector`.",
        ))
        push!(selectors, selector)

        raw_group isa AbstractDict || throw(ArgumentError(
            "$constraint_name group `$selector` must be an object.",
        ))
        group_keys = Set(Symbol(key) for key in keys(raw_group))
        unknown_keys = setdiff(group_keys, Set((:edge, :value)))
        isempty(unknown_keys) || throw(ArgumentError(
            "$constraint_name group `$selector` has unknown key(s): $(collect(unknown_keys)).",
        ))
        haskey(raw_group, :edge) || throw(ArgumentError(
            "$constraint_name group `$selector` requires an `edge` key.",
        ))
        haskey(raw_group, :value) || throw(ArgumentError(
            "$constraint_name group `$selector` requires a `value` key.",
        ))

        raw_edge = raw_group[:edge]
        raw_edge isa Union{Symbol,AbstractString} || throw(ArgumentError(
            "$constraint_name group `$selector` has a non-string `edge`.",
        ))
        raw_value = raw_group[:value]
        raw_value isa Real || throw(ArgumentError(
            "$constraint_name group `$selector` has a non-numeric `value`.",
        ))
        value = Float64(raw_value)
        isnan(value) && throw(ArgumentError(
            "$constraint_name group `$selector` has an invalid `value`.",
        ))

        push!(groups, G(selector, Symbol(raw_edge), value))
    end

    return C(groups)
end

"""
    resolve_assets_by_type_key(system, key)

Resolve a grouped-constraint selector to matching assets. A defined asset type uses Julia
subtyping; exact parametric names and wildcards fall back to the existing string selector helper.
"""
function resolve_assets_by_type_key(system::System, key::Symbol)
    if isdefined(MacroEnergy, key)
        T = getfield(MacroEnergy, key)
        if isa(T, Type) && T <: AbstractAsset
            return filter(a -> isa(a, T), system.assets)
        end
    end
    type_strings = get_type.(system.assets)
    matched = Set(first(search_assets(string(key), unique(type_strings))))
    return [a for (a, type_string) in zip(system.assets, type_strings) if type_string in matched]
end

# The capacity location is the edge's explicit location when set. Otherwise, use a connected
# vertex, preferring the end vertex (usually the receiving bus) to the start vertex.
function capped_edge_location(e::AbstractEdge)
    ismissing(e.location) || return e.location
    for vertex in (end_vertex(e), start_vertex(e))
        ismissing(location(vertex)) || return location(vertex)
    end
    return missing
end

"""
    build_grouped_capacity_constraints(config, system, model; variable, sense, constraint_name, location)

Build one capacity-like constraint for each group in `config` and return its JuMP references,
keyed by selector. `variable` selects the summed quantity (`capacity` or `new_capacity`).
"""
function build_grouped_capacity_constraints(
    config::AbstractGroupedConstraintConfig,
    system::System,
    model::Model;
    variable::Function,
    sense::Symbol,
    constraint_name::String,
    location::Union{Missing,Symbol}=missing,
)
    refs = Dict{Symbol,Any}()
    for group in constraint_groups(config)
        selector = group_selector(group)
        assets = resolve_assets_by_type_key(system, selector)
        if isempty(assets)
            @warn "$constraint_name: asset type `$selector` matched no assets in the system; skipping"
            continue
        end

        edge_field = group_edge(group)
        total = AffExpr(0.0)
        contributed = false
        for asset in assets
            edge_field in fieldnames(typeof(asset)) || error(
                "$constraint_name: asset type $selector (`$(get_type(asset))`) has no edge field `$edge_field`",
            )
            edge = get_component_by_fieldname(asset, edge_field)
            if !has_capacity(edge)
                @warn "$constraint_name: edge field `$edge_field` of asset $(id(asset)) (`$(get_type(asset))`) has no capacity variable; skipping"
                continue
            end
            ismissing(location) || capped_edge_location(edge) == location || continue
            add_to_expression!(total, variable(edge))
            contributed = true
        end
        contributed || continue

        refs[selector] = sense === :leq ?
            @constraint(model, total <= group_value(group)) :
            @constraint(model, total >= group_value(group))
    end
    return refs
end

function scale_grouped_constraint_config(
    config::C,
    factor::Float64,
) where {C<:AbstractGroupedConstraintConfig}
    groups = [
        typeof(group)(group_selector(group), group_edge(group), group_value(group) * factor)
        for group in constraint_groups(config)
    ]
    return C(groups)
end

function add_constraints_by_type!(system::System, model::Model, constraint_type::DataType)

    for n in system.locations
        add_constraints_by_type!(n, model, constraint_type)
    end

    for a in system.assets
        for t in fieldnames(typeof(a))
            add_constraints_by_type!(getfield(a, t), model, constraint_type)
        end
    end

    for c in system.constraints
        if isa(c, constraint_type)
            add_model_constraint!(c, system, model)
        end
    end

    return nothing
end

function add_constraints_by_type!(
    y::Union{AbstractEdge,AbstractVertex},
    model::Model,
    ::Type{C},
) where {C<:AbstractTypeConstraint}
    for c in all_constraints(y)
        if c isa C
            add_model_constraint!(c, y, model)
        end
    end

    return nothing
end

function add_constraints_by_type!(
    location::Location,
    model::Model,
    ::Type{C},
) where {C<:AbstractTypeConstraint}
    for c in all_constraints(location)
        if c isa C
            add_model_constraint!(c, location, model)
        end
    end
    return nothing
end

const CONSTRAINT_TYPES = Dict{Symbol,DataType}()

function register_constraint_types!(m::Module = MacroEnergy)
    empty!(CONSTRAINT_TYPES)
    for (constraint_name, constraint_type) in all_subtypes(m, :AbstractTypeConstraint)
        CONSTRAINT_TYPES[constraint_name] = constraint_type
    end
    return nothing
end

function constraint_types(m::Module = MacroEnergy)
    isempty(CONSTRAINT_TYPES) && register_constraint_types!(m)
    return CONSTRAINT_TYPES
end
