function compare(a,b)
    return a == b
end

function compare(a::Missing,b)
    return ismissing(b)
end

function compare(a,b::Missing)
    return ismissing(a)
end

function compare(a::Missing,b::Missing)
    return true
end

function Base.:(==)(a::T, b::T) where {T<:Union{MacroObject,AbstractTimeData,AbstractTypeConstraint}}
    return all([compare(getproperty(a,prop), getproperty(b,prop)) for prop in propertynames(a)])
end

function fun_check(f::Symbol, a, b, m::Module=MacroEnergy)
    fun = getproperty(m, f)
    try
        return compare(fun(a), fun(b), false, m)
    catch e
        if isa(e, MethodError)
            return compare(getproperty(a,f), getproperty(b,f), false, m)
        else
            return false
        end
    end
end

function fun_check(f::Symbol, a, b, idx, m::Module=MacroEnergy)
    fun = getproperty(m, f)
    try
        return compare(fun(a, idx), fun(b, idx), false, m)
    catch e
        if isa(e, MethodError)
            return compare(getproperty(a,f), getproperty(b,f), false, m)
        else
            return false
        end
    end
end

function compare(a, b, checkfunctions::Bool, m::Module=MacroEnergy)
    return compare(a,b)
end

function compare(a::T, b::T, propname::Symbol, checkfunctions::Bool=false, m::Module=MacroEnergy) where {T<:Union{MacroObject,AbstractTimeData,AbstractTypeConstraint}}
    @debug("Comparing property: $propname")
    if MacroEnergy.compare(getproperty(a,propname), getproperty(b,propname), checkfunctions, m)
        @debug("Data matched for $propname")
        return true
    end
    if checkfunctions && isdefined(m, propname)
        check1 = fun_check(propname, a, b)
        check2 = fun_check(propname, a, b, 1)
        @debug("Function comparison: $(check1 || check2) for $propname")
        return check1 || check2
    else
        @debug("Data did not match for $propname")
        return false
    end
end

function compare(a::T, b::T, checkfunctions::Bool=false, m::Module=MacroEnergy) where {T<:Union{MacroObject,AbstractTimeData,AbstractTypeConstraint}}
    comparisons = Bool[]
    for propname in propertynames(a)
        push!(comparisons, compare(a, b, propname, checkfunctions, m))
    end
    return all(comparisons)
end

function compare(a::AbstractStorage, b::AbstractStorage, checkfunctions::Bool=false, m::Module=MacroEnergy)
    comparisons = Bool[]
    for propname in propertynames(a)
        @debug("Comparing property: $propname")
        prop_a = getproperty(a, propname)
        prop_b = getproperty(b, propname)
        if isa(prop_a, AbstractEdge)
            @debug("Comparing edge property: $propname")
            test_result = compare(id(prop_a), id(prop_b), checkfunctions, m)
            @debug("Test 1: $(test_result)")
            push!(comparisons, test_result)
            continue
        end
        push!(comparisons, compare(a, b, propname, checkfunctions, m))
    end
    return all(comparisons)
end

function find_diff(a::T, b::T, checkfunctions::Bool=false, m::Module=MacroEnergy) where {T<:Union{MacroObject,AbstractTimeData,AbstractTypeConstraint}}
    return [prop for prop in propertynames(a) if !MacroEnergy.compare(getproperty(a,prop), getproperty(b,prop), checkfunctions, m)]
end

function Base.hash(a::T, h::UInt) where {T<:Union{MacroObject,AbstractTimeData,AbstractTypeConstraint}}
    ht = hash(T, h)
    for prop_name in propertynames(a)
        prop = getproperty(a, prop_name)
        if isa(prop, AbstractEdge)
            ht = hash(id(prop), ht)
        else
            ht = hash(prop, ht)
        end
    end
    return ht
end

function compare_assets(a::AbstractSystem, b::AbstractSystem, checkfunctions::Bool=false, m::Module=MacroEnergy; verbose::Bool=false)
    if !verbose
        return all(compare.(a.assets, b.assets, Ref(checkfunctions), Ref(m)))
    else
        comparisons = Bool[]
        for (idx, asset_a) in enumerate(a.assets)
            asset_b = get_asset_by_id(b, asset_a.id)
            id_a = asset_a.id
            if isnothing(asset_b)
                @debug("$(asset_a.id) not found in second system")
                status = "⁉"
                id_b = "N/A"
                push!(comparisons, false)
                diff_string = ""
            else
                # test_result = compare(asset_a, asset_b, checkfunctions, m)
                # diff_string = ""
                diff = find_diff(asset_a, asset_b, checkfunctions, m)
                if isempty(diff)
                    test_result = true
                else
                    test_result = false
                end
                status = test_result ? "🟩" : "🟥"
                diff_string = isempty(diff) ? "" : "\n   -- Diff in: $(diff)"
                push!(comparisons, test_result)
                id_b = asset_b.id
            end
            println("#$idx: $status | $id_a | $id_b" * diff_string)
        end
        return all(comparisons)
    end
end