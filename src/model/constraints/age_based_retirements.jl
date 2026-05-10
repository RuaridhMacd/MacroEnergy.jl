Base.@kwdef mutable struct AgeBasedRetirementConstraint <: PlanningConstraint
    value::Union{Missing,Vector{Float64}} = missing
    constraint_dual::Union{Missing,Vector{Float64}} = missing
    constraint_ref::Union{Missing,JuMPConstraint} = missing
end

function add_model_constraint!(ct::AgeBasedRetirementConstraint, y::Union{AbstractEdge,AbstractStorage}, model::Model)
    
    curr_period = period_index(y);
    ret_period = retirement_period(y);


    #### All new capacity built up to the retirement period must either retire or be retrofitted in the current period
    ct.constraint_ref = @constraint(
        model, 
        sum(new_capacity_track(y,k) for k=1:ret_period;init=0) + min_retired_capacity_track(y) <= sum(retired_capacity_track(y,k) for k=1:curr_period) + sum(retrofitted_capacity_track(y,k) for k=1:curr_period)
    )
        

    return nothing
end

function add_model_constraint!(
    ct::AgeBasedRetirementConstraint,
    y::Union{AbstractEdge,AbstractStorage},
    problem::AbstractProblem,
)
    jump_model = model(problem)
    refs = capacity_refs(get_component_refs(problem.refs, y))
    curr_period = period_index(y)
    ret_period = retirement_period(y)

    refs.constraints[AgeBasedRetirementConstraint] = @constraint(
        jump_model,
        sum(new_capacity_track(refs, k) for k in 1:ret_period; init = 0) +
        min_retired_capacity_track(y) <=
        sum(retired_capacity_track(refs, k) for k in 1:curr_period; init = 0) +
        sum(retrofitted_capacity_track(refs, k) for k in 1:curr_period; init = 0)
    )

    return nothing
end
