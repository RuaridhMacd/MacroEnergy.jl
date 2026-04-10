Base.@kwdef struct UpdateTarget
    component_type::Symbol
    component_index::Int
    field::Symbol
end

Base.@kwdef struct UpdateInstruction
    kind::Symbol
    target::UpdateTarget
    payload::Any = nothing
end

Base.@kwdef struct UpdateMap
    instructions::Vector{UpdateInstruction} = UpdateInstruction[]
end

