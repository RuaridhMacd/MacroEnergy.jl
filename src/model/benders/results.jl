"""Convergence diagnostics from a completed Benders solve."""
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

"""A container for a Benders problem. Mirrors JuMP's `Model` pattern:
`generate_model` sets up the problem (including subproblem initialization),
`optimize!` runs the Benders solve, extracts results, and stores them in the
`planning_sol`, `subop_sol`, and `convergence` fields."""
mutable struct BendersModel
    settings::NamedTuple
    update_target::Union{Case, System}
    planning_problem::Model
    subproblems::Union{Vector{Dict{Any, Any}}, DistributedArrays.DArray}
    linking_variables_sub::Dict
    planning_sol::Union{NamedTuple, Nothing}
    subop_sol::Union{Dict{Any, Any}, Nothing}
    convergence::Union{BendersConvergence, Nothing}
end

# Convenience constructor for BendersModel when planning_sol, subop_sol, and convergence are not yet available
# they will be populated after optimize! is called
BendersModel(settings, target, planning_problem, subproblems, linking_variables_sub) =
    BendersModel(settings, target, planning_problem, subproblems, linking_variables_sub, nothing, nothing, nothing)