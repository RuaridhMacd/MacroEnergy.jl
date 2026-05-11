struct MyopicResults
    results::Union{Vector, Nothing}
end

function load_previous_capacity_results(path::AbstractString)
    df = load_dataframe(path)
    if all(["component_id", "capacity", "new_capacity", "retired_capacity"] .∈ Ref(names(df)))
        #### The dataframe has wide format
        return df
    elseif all(["component_id", "variable", "value"] .∈ Ref(names(df)))
        #### The dataframe has long format, reshape to wide
        return reshape_wide(df, :variable, :value)
    else
        error("The capacity results file at $(path) does not have the expected format. It should contain either (component_id, capacity, new_capacity, retired_capacity) columns in wide format or (component_id, variable, value) columns in long format.")
    end
end

function carry_over_capacities!(system::System, prev_results::Dict{Int64,DataFrame}, last_period::Int)

    all_edges = get_edges(system)
    storages = get_storages(system)
    edges_with_capacity = edges_with_capacity_variables(all_edges)
    components_with_capacity = vcat(edges_with_capacity, storages)
    for y in components_with_capacity
        df_restart = prev_results[last_period]
        component_row = findfirst(df_restart.component_id .== String(id(y)))
        if isnothing(component_row)
            @info("Skipping component $(id(y)) as it was not present in the previous period")
        else
            y.existing_capacity = df_restart.capacity[component_row]
            for prev_period in keys(prev_results)
                df = prev_results[prev_period];
                component_row = findfirst(df.component_id .== String(id(y)))
                if !isnothing(component_row)
                    y.new_capacity_track[prev_period] = df.new_capacity[component_row]
                    y.retired_capacity_track[prev_period] = df.retired_capacity[component_row]
                    if isa(y, AbstractEdge) && "retrofitted_capacity" ∈ names(df)
                        y.retrofitted_capacity_track[prev_period] = df.retrofitted_capacity[component_row]
                    end
                end
            end
        end
    end
end

function carry_over_solved_capacities!(system::System, system_prev::System)

    for a in system.assets
        a_prev_index = findfirst(id.(system_prev.assets).==id(a))
        if isnothing(a_prev_index)
            @info("Skipping asset $(id(a)) as it was not present in the previous period")
            validate_existing_capacity(a)
        else
            a_prev = system_prev.assets[a_prev_index];
            carry_over_solved_capacities!(a, a_prev)
        end
    end

end

function carry_over_solved_capacities!(a::AbstractAsset, a_prev::AbstractAsset)

    for t in fieldnames(typeof(a))
        carry_over_solved_capacities!(getfield(a,t), getfield(a_prev,t))
    end

end

solved_capacity_value(x::Number) = Float64(x)
solved_capacity_value(x) = value(x)

function carry_over_solved_capacity!(
    y::Union{AbstractEdge,AbstractStorage},
    y_prev::Union{AbstractEdge,AbstractStorage},
)
    has_capacity(y_prev) || return nothing

    y.existing_capacity = solved_capacity_value(capacity(y_prev))

    for prev_period in keys(new_capacity_track(y_prev))
        y.new_capacity_track[prev_period] = solved_capacity_value(new_capacity_track(y_prev, prev_period))
        y.retired_capacity_track[prev_period] = solved_capacity_value(retired_capacity_track(y_prev, prev_period))

        if isa(y, AbstractEdge)
            y.retrofitted_capacity_track[prev_period] =
                solved_capacity_value(retrofitted_capacity_track(y_prev, prev_period))
        end
    end
    return nothing
end

function carry_over_solved_capacities!(y::Union{AbstractEdge,AbstractStorage},y_prev::Union{AbstractEdge,AbstractStorage})
    carry_over_solved_capacity!(y, y_prev)
end

function carry_over_solved_capacities!(g::Transformation,g_prev::Transformation)
    return nothing
end

function carry_over_solved_capacities!(n::Node,n_prev::Node)
    return nothing
end
