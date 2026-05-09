Base.@kwdef mutable struct LongDurationStorageChangeConstraint <: OperationConstraint
    value::Union{Missing,Vector{Float64}} = missing
    constraint_dual::Union{Missing,Vector{Float64}} = missing
    constraint_ref::Union{Missing,JuMPConstraint} = missing
end

function add_model_constraint!(ct::LongDurationStorageChangeConstraint, g::LongDurationStorage, model::Model)
    subperiod_end = Dict(w => last(get_subperiod(g, w)) for w in subperiod_indices(g));

    ct.constraint_ref = @constraint(model, 
                        [w in subperiod_indices(g)], 
                        storage_initial(g, w) ==  storage_level(g,subperiod_end[w]) - storage_change(g, w)
                        )
    return nothing
end

function add_model_constraint!(
    ct::LongDurationStorageChangeConstraint,
    g::LongDurationStorage,
    problem::AbstractProblem,
)
    model, refs = constraint_model_and_refs(g, problem)
    subperiod_end = Dict(w => last(get_subperiod(g, w)) for w in subperiod_indices(g))

    ct.constraint_ref = @constraint(
        model,
        [w in subperiod_indices(g)],
        storage_initial(refs, w) == storage_level(refs, subperiod_end[w]) - storage_change(refs, w)
    )
    return nothing
end
