function filter_input_data(data::AbstractDict{Symbol, Any}, type, keys_to_remove::Vector{Symbol}=Symbol[], tracking_var_keys::Vector{Symbol}=Symbol[])
    kwargs = Base.fieldnames(type)
    kwargs = filter(x -> !(x in keys_to_remove) && !(x in tracking_var_keys), kwargs)
    filtered_data = Dict{Symbol, Any}(
        k => v for (k,v) in data if (k in kwargs) && !(v == "")
    )
    for k in tracking_var_keys
        if haskey(data, k)
            filtered_data[k] = Dict{Int64,AffExpr}(
                parse(Int64,String(kk)) => AffExpr(vv) for (kk,vv) in data[k]
            )
        end
    end
    if haskey(filtered_data,:loss_fraction) && !isa(filtered_data[:loss_fraction], AbstractVector)
        filtered_data[:loss_fraction] = [filtered_data[:loss_fraction]];
    end
    filtered_data[:warm_starts] = get(filtered_data, :warm_starts, Dict{Symbol,Any}())
    for k in kwargs
        if haskey(filtered_data, k) && isa(filtered_data[k], Real) && fieldtype(type, k) in [Union{JuMPVariable, AffExpr}, Union{Missing, JuMPVariable}, JuMPVariable, AffExpr]
            filtered_data[:warm_starts][k] = filtered_data[k]
            delete!(filtered_data, k)
        end
    end
    return filtered_data
end