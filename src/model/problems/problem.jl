Base.@kwdef struct Problem <: AbstractProblem
    spec::ProblemSpec
    model::Model = Model()
    refs::ProblemRefs
end

function Problem(
    spec::ProblemSpec;
    model::Model=Model(),
    refs::ProblemRefs=ProblemRefs(spec),
)
    return Problem(
        spec = spec,
        model = model,
        refs = refs,
    )
end

function Problem(
    static_system::StaticSystem;
    id::Symbol=:problem,
    model::Model=Model(),
)
    spec = full_problem_spec(static_system; id)
    return Problem(spec; model, refs=ProblemRefs(static_system, spec))
end

function Problem(
    static_systems::AbstractVector{StaticSystem};
    id::Symbol=:problem,
    model::Model=Model(),
)
    spec = full_problem_spec(static_systems; id)
    return Problem(spec; model, refs=ProblemRefs(static_systems, spec))
end

function Problem(
    static_system::StaticSystem,
    ::Nothing;
    id::Symbol=:problem,
    model::Model=Model(),
)
    spec = full_problem_spec(static_system; id)
    return Problem(spec; model, refs=ProblemRefs(static_system, spec))
end

function Problem(
    static_systems::AbstractVector{StaticSystem},
    ::Nothing;
    id::Symbol=:problem,
    model::Model=Model(),
)
    spec = full_problem_spec(static_systems; id)
    return Problem(spec; model, refs=ProblemRefs(static_systems, spec))
end

function Problem(
    static_system::StaticSystem,
    spec::ProblemSpec;
    model::Model=Model(),
)
    return Problem(spec; model, refs=ProblemRefs(static_system, spec))
end

function Problem(
    static_systems::AbstractVector{StaticSystem},
    spec::ProblemSpec;
    model::Model=Model(),
)
    return Problem(spec; model, refs=ProblemRefs(static_systems, spec))
end

function optimize!(p::Problem)
    return JuMP.optimize!(p.model)
end

model(p::Problem) = p.model
model(m::Model) = m
id(p::Problem) = p.spec.id

Base.getindex(p::Problem, key) = p.model[key]
Base.setindex!(p::Problem, value, key) = setindex!(p.model, value, key)
Base.haskey(p::Problem, key) = haskey(p.model, key)

JuMP.objective_value(p::Problem; kwargs...) = JuMP.objective_value(p.model; kwargs...)
JuMP.termination_status(p::Problem) = JuMP.termination_status(p.model)
JuMP.primal_status(p::Problem) = JuMP.primal_status(p.model)
JuMP.dual_status(p::Problem) = JuMP.dual_status(p.model)
JuMP.set_silent(p::Problem) = JuMP.set_silent(p.model)
JuMP.unset_silent(p::Problem) = JuMP.unset_silent(p.model)
JuMP.has_values(p::Problem) = JuMP.has_values(p.model)
JuMP.has_duals(p::Problem) = JuMP.has_duals(p.model)
JuMP.assert_is_solved_and_feasible(p::Problem; kwargs...) =
    JuMP.assert_is_solved_and_feasible(p.model; kwargs...)
