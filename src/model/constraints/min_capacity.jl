Base.@kwdef mutable struct MinCapacityConstraint <: PlanningConstraint
    value::Union{Missing,Vector{Float64}} = missing
    constraint_dual::Union{Missing,Vector{Float64}} = missing
    constraint_ref::Union{Missing,JuMPConstraint} = missing
end

@doc raw"""
    add_model_constraint!(ct::MinCapacityConstraint, y::Union{AbstractEdge,AbstractStorage}, model::Model)

Add a min capacity constraint to the edge or storage `y`. The functional form of the constraint is:

```math
\begin{aligned}
    \text{capacity(y)} \geq \text{min\_capacity(y)}
\end{aligned}
```
"""
function add_model_constraint!(ct::MinCapacityConstraint, y::Union{AbstractEdge,AbstractStorage}, model::Model)

    ct.constraint_ref = @constraint(model, capacity(y) >= min_capacity(y))

    return nothing
end

function add_model_constraint!(
    ct::MinCapacityConstraint,
    y::AbstractEdge,
    problem::AbstractProblem,
)
    jump_model, refs = constraint_model_and_refs(y, problem)
    refs.constraints[typeof(ct)] = @constraint(jump_model, capacity(refs) >= min_capacity(y))
    return nothing
end

function add_model_constraint!(
    ct::MinCapacityConstraint,
    y::AbstractStorage,
    problem::AbstractProblem,
)
    jump_model, refs = constraint_model_and_refs(y, problem)
    refs.constraints[typeof(ct)] = @constraint(jump_model, capacity(refs) >= min_capacity(y))
    return nothing
end
