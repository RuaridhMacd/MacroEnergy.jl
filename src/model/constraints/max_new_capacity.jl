Base.@kwdef mutable struct MaxNewCapacityConstraint <: PlanningConstraint
    value::Union{Missing,Vector{Float64}} = missing
    constraint_dual::Union{Missing,Vector{Float64}} = missing
    constraint_ref::Union{Missing,JuMPConstraint} = missing
end


function add_model_constraint!(ct::MaxNewCapacityConstraint, y::Union{AbstractEdge,AbstractStorage}, model::Model)

    ct.constraint_ref = @constraint(model, new_capacity(y) <= max_new_capacity(y))

    return nothing

end

function add_model_constraint!(
    ct::MaxNewCapacityConstraint,
    y::AbstractEdge,
    problem::AbstractProblem,
)
    jump_model, refs = constraint_model_and_refs(y, problem)
    refs.constraints[typeof(ct)] = @constraint(jump_model, new_capacity(refs) <= max_new_capacity(y))
    return nothing
end

function add_model_constraint!(
    ct::MaxNewCapacityConstraint,
    y::AbstractStorage,
    problem::AbstractProblem,
)
    jump_model, refs = constraint_model_and_refs(y, problem)
    refs.constraints[typeof(ct)] = @constraint(jump_model, new_capacity(refs) <= max_new_capacity(y))
    return nothing
end
