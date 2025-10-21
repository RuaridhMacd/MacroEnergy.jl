Base.@kwdef mutable struct BalanceConstraint <: OperationConstraint
    value::Union{Missing,Vector{Float64}} = missing
    lagrangian_multiplier::Union{Missing,Vector{Float64}} = missing
    constraint_ref::Union{Missing,JuMPConstraint} = missing
end

@doc raw"""
    add_model_constraint!(ct::BalanceConstraint, v::AbstractVertex, model::Model)

Add a balance constraint to the vertex `v`. 

- If `v` is a `Node`, a demand balance constraint is added. 
- If `v` is a `Transformation`, this constraint ensures that the stoichiometric equations linking the input and output flows are correctly balanced.

```math
\begin{aligned}
    \sum_{\substack{i\  \in \ \text{balance\_eqs\_ids(v)}, \\ t\  \in \ \text{time\_interval(v)}} } \text{balance\_eq(v, i, t)} = 0.0
\end{aligned}
```
"""
function add_model_constraint!(ct::BalanceConstraint, v::AbstractVertex, model::Model)

    ct.constraint_ref = @constraint(
        model,
        [i in balance_ids(v), t in time_interval(v)],
        get_balance(v, i, t) == 0.0
    )

    return nothing
end

"""
    set_constraint_dual!(constraint::BalanceConstraint, node::Node)

Extract and store dual values from a BalanceConstraint on the :demand balance equation 
for a given node.

# Arguments
- `constraint::BalanceConstraint`: The balance constraint to set the dual values for
- `node::Node`: The node containing the balance constraint

# Returns
- `nothing`. The dual values are stored in the `lagrangian_multiplier` field of the constraint.

This function extracts dual values from the constraint reference and stores them in a 
vector in the `lagrangian_multiplier` field.
"""
function set_constraint_dual!(
    constraint::BalanceConstraint,
    node::Node,
)
    # Check if constraint has a reference
    if ismissing(constraint.constraint_ref)
        error("BalanceConstraint on node $(id(node)) has no constraint reference")
    end

    constraint.lagrangian_multiplier = dual.(constraint.constraint_ref[:demand,:].data)

    return nothing
end