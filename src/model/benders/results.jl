"""
    BendersConvergence

A struct to hold convergence diagnostics from a completed Benders solve, including iteration history of lower and upper bounds, optimality gap, termination status, and CPU time.

# Fields
- `LB_hist::Vector{Float64}`: History of lower bounds across iterations.
- `UB_hist::Vector{Float64}`: History of upper bounds across iterations.
- `gap_hist::Vector{Float64}`: History of optimality gap across iterations.
- `termination_status::AbstractString`: Termination status of the Benders solve (e.g. "Optimal", "Infeasible", etc.).
- `cpu_time::Vector{Float64}`: History of CPU time taken for each iteration.
"""
struct BendersConvergence
    LB_hist::Vector{Float64}
    UB_hist::Vector{Float64}
    gap_hist::Vector{Float64}
    termination_status::AbstractString
    cpu_time::Vector{Float64}
end

BendersConvergence(nt::NamedTuple) = BendersConvergence(
    nt.LB_hist, nt.UB_hist, nt.gap_hist, nt.termination_status, nt.cpu_time
)

Base.@kwdef struct BendersLinkKey
    component_key::ComponentRefKey
    field::Symbol
    index::Tuple = ()
end

Base.@kwdef mutable struct BendersProblem <: AbstractProblem
    settings::NamedTuple
    planning::Problem
    subproblems::Union{Vector{Dict{Any,Any}},DistributedArrays.DArray}
    planning_variables::Vector
    linking_variables_sub::Dict
    period_to_subproblem_map::Dict{Int,Vector{Int}}
    planning_sol::Union{NamedTuple,Nothing} = nothing
    subop_sol::Union{Dict{Any,Any},Nothing} = nothing
    convergence::Union{BendersConvergence,Nothing} = nothing
end

model(bp::BendersProblem) = model(bp.planning)
id(bp::BendersProblem) = id(bp.planning)
