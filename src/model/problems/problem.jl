Base.@kwdef struct Problem
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
    return Problem(spec; model)
end

function Problem(
    static_system::StaticSystem,
    ::Nothing;
    id::Symbol=:problem,
    model::Model=Model(),
)
    spec = full_problem_spec(static_system; id)
    return Problem(spec; model)
end

function Problem(
    ::StaticSystem,
    spec::ProblemSpec;
    model::Model=Model(),
)
    return Problem(spec; model)
end

function optimize!(p::Problem)
    return JuMP.optimize!(p.model)
end

model(p::Problem) = p.model
model(m::Model) = m
id(p::Problem) = p.spec.id
