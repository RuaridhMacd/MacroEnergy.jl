Base.@kwdef struct UpdateTarget
    component_type::Symbol
    component_index::Int
    field::Symbol
end

Base.@kwdef mutable struct UpdateInstruction
    kind::Symbol
    target::UpdateTarget
    ref::Any = nothing
    source_key::Union{Nothing,String} = nothing
    metadata::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

Base.@kwdef mutable struct UpdateMap
    instructions::Vector{UpdateInstruction} = UpdateInstruction[]
end

function clear_updates!(update_map::UpdateMap; kind::Union{Nothing,Symbol}=nothing)
    if isnothing(kind)
        empty!(update_map.instructions)
    else
        filter!(instruction -> instruction.kind != kind, update_map.instructions)
    end
    return update_map
end

function register_fix_update!(
    update_map::UpdateMap;
    component_type::Symbol,
    component_index::Int,
    field::Symbol,
    ref,
    source_key::String,
    metadata::Dict{Symbol,Any}=Dict{Symbol,Any}(),
)
    push!(
        update_map.instructions,
        UpdateInstruction(
            kind = :fix,
            target = UpdateTarget(
                component_type = component_type,
                component_index = component_index,
                field = field,
            ),
            ref = ref,
            source_key = source_key,
            metadata = metadata,
        ),
    )
    return update_map
end

fix_update_instructions(update_map::UpdateMap) =
    filter(instruction -> instruction.kind == :fix, update_map.instructions)

function apply_update!(instruction::UpdateInstruction, source_values::AbstractDict)
    if instruction.kind != :fix
        error("Unsupported update instruction kind $(instruction.kind).")
    end

    isnothing(instruction.source_key) &&
        error("Cannot apply fix update without a source key.")
    ismissing(get(source_values, instruction.source_key, missing)) &&
        error("Missing value for update key $(instruction.source_key).")

    variable_ref = instruction.ref
    target_value = source_values[instruction.source_key]

    fix(variable_ref, target_value; force=true)
    if is_integer(variable_ref)
        unset_integer(variable_ref)
    elseif is_binary(variable_ref)
        unset_binary(variable_ref)
    end

    return nothing
end

function apply_updates!(
    update_map::UpdateMap,
    source_values::AbstractDict;
    kind::Union{Nothing,Symbol}=nothing,
)
    for instruction in update_map.instructions
        if isnothing(kind) || instruction.kind == kind
            apply_update!(instruction, source_values)
        end
    end
    return nothing
end
