const COMMODITY_TYPES = Dict{Symbol,DataType}()

function register_commodity_types!(m::Module = MacroEnergy)
    empty!(COMMODITY_TYPES)
    for (commodity_name, commodity_type) in all_subtypes(m, :Commodity)
        COMMODITY_TYPES[commodity_name] = commodity_type
    end
end

function commodity_types(m::Module = MacroEnergy)
    isempty(COMMODITY_TYPES) && register_commodity_types!(m)
    return COMMODITY_TYPES
end

###### ###### ###### ######

function clean_line(line::AbstractString)::String
    return join(split(strip(line)), " ")
end

function make_commodity(new_commodity::Union{String,Symbol}, m::Module = MacroEnergy)::String
    s = "abstract type $new_commodity <: $m.Commodity end"
    Core.eval(m, Meta.parse(s))
    return s
end

function make_commodity(new_commodity::Union{String,Symbol}, parent_type::Union{String,Symbol}, m::Module = MacroEnergy)::String
    s = "abstract type $new_commodity <: $m.$parent_type end"
    Core.eval(m, Meta.parse(s))
    return s
end

function make_commodity(new_commodity::Union{String,Symbol}, parent_type::DataType, m::Module = MacroEnergy)::String
    return make_commodity(new_commodity, typesymbol(parent_type), m)
end

###### ###### ###### ######

function load_commodities_from_file(path::AbstractString, rel_path::AbstractString; write_subcommodities::Bool=false)
    path = rel_or_abs_path(path, rel_path)
    if isdir(path)
        path = joinpath(path, "commodities.json")
    end
    # read in the list of commodities from the data directory
    isfile(path) || error("Commodity data not found at $(abspath(path))")
    return load_commodities(copy(read_json(path)), rel_path; write_subcommodities=write_subcommodities)
end

function load_commodities(data::AbstractDict{Symbol,Any}, rel_path::AbstractString; write_subcommodities::Bool=false)
    if haskey(data, :path)
        path = rel_or_abs_path(data[:path], rel_path)
        return load_commodities_from_file(path, rel_path; write_subcommodities=write_subcommodities)
    elseif haskey(data, :commodities)
        return load_commodities(data[:commodities], rel_path; write_subcommodities=write_subcommodities)
    end
    return nothing
end

function load_commodities(data::AbstractVector{Dict{Symbol,Any}}, rel_path::AbstractString; write_subcommodities::Bool=false)
    for item in data
        if isa(item, AbstractDict{Symbol,Any}) && haskey(item, :commodities)
            return load_commodities(item, rel_path; write_subcommodities=write_subcommodities)
        end
    end
    error("Commodity data not found or incorrectly formatted in system_data")
end

function load_commodities(data::AbstractVector{<:AbstractString}, rel_path::AbstractString; write_subcommodities::Bool=false)
    # Probably means we have a vector of commdity types
    return load_commodities(Symbol.(data); write_subcommodities=write_subcommodities)
end

function parse_commodity_inputs(
    commodities::AbstractVector{<:Any},
    macro_commodities::AbstractDict{Symbol,DataType},
)
    user_subcommodities = Dict{Symbol,Any}[]
    system_commodities = Symbol[]

    for commodity in commodities
        if isa(commodity, Symbol)
            if commodity ∉ keys(macro_commodities)
                error("Unknown commodity: $commodity")
            end
            push!(system_commodities, commodity)
        elseif isa(commodity, AbstractString)
            commodity_symbol = Symbol(commodity)
            if commodity_symbol ∉ keys(macro_commodities)
                error("Unknown commodity: $commodity")
            end
            push!(system_commodities, commodity_symbol)
        elseif isa(commodity, Dict) && haskey(commodity, :name) && haskey(commodity, :acts_like)
            push!(user_subcommodities, commodity)
            push!(system_commodities, Symbol(commodity[:name]))
        else
            error("Invalid commodity format: $commodity")
        end
    end

    return user_subcommodities, system_commodities
end

function add_subcommodity!(
    commodity::AbstractDict{Symbol,Any},
    commodity_keys,
    subcommodities_lines::AbstractVector{String};
    write_subcommodities::Bool=false,
)::Bool
    @debug("Iterating over user-defined subcommodities")
    new_name = Symbol(commodity[:name])
    parent_name = Symbol(commodity[:acts_like])

    if new_name in commodity_keys
        @debug("Commodity $(commodity[:name]) already exists")
        return true
    end

    if parent_name ∉ commodity_keys
        return false
    end

    @debug("Adding subcommodity $(new_name), which acts like commodity $(parent_name)")
    commodity_line = make_commodity(new_name, parent_name)
    COMMODITY_TYPES[new_name] = Base.invokelatest(getfield, MacroEnergy, new_name)
    if write_subcommodities
        @debug("Will write subcommodity $(new_name) to file")
        push!(subcommodities_lines, commodity_line)
    end
    return true
end

function resolve_subcommodities!(
    user_subcommodities::AbstractVector{<:AbstractDict{Symbol,Any}},
    subcommodities_lines::AbstractVector{String};
    write_subcommodities::Bool=false,
)
    unresolved = collect(user_subcommodities)

    while !isempty(unresolved)
        progress = false
        next_unresolved = Dict{Symbol,Any}[]
        commodity_keys = keys(commodity_types())

        for commodity in unresolved
            was_resolved = add_subcommodity!(
                commodity,
                commodity_keys,
                subcommodities_lines;
                write_subcommodities=write_subcommodities,
            )
            if was_resolved
                progress = true
            else
                push!(next_unresolved, commodity)
            end
        end

        if !progress
            unknown_parents = unique(Symbol(c[:acts_like]) for c in unresolved)
            error("Unknown or circular parent commodities: $unknown_parents")
        end

        unresolved = next_unresolved
    end

    return nothing
end

function load_commodities(commodities::AbstractVector{<:Any}, rel_path::AbstractString=""; write_subcommodities::Bool=false)
    register_commodity_types!()

    macro_commodities = commodity_types()
    all_sub_commodities, system_commodities = parse_commodity_inputs(commodities, macro_commodities)

    subcommodities_lines = String[]
    resolve_subcommodities!(all_sub_commodities, subcommodities_lines; write_subcommodities=write_subcommodities)
    @debug(" -- Done adding subcommodities")

    if write_subcommodities && !isempty(subcommodities_lines)
        write_user_subcommodities(rel_path, subcommodities_lines)
        @debug(" -- Done writing subcommodities")
    end
    # get the list of all commodities available
    macro_commodity_types = commodity_types();
    # return a dictionary of system commodities Dict{Symbol, DataType}
    return Dict(k=>macro_commodity_types[k] for k in system_commodities)
end

load_commodities(commodities::AbstractVector{<:AbstractString}) =
    load_commodities(Symbol.(commodities))

function load_commodities(commodities::Vector{Symbol})
    # get the list of all commodities available
    macro_commodities = commodity_types()

    validate_commodities(commodities)

    # return a dictionary of commodities Dict{Symbol, DataType}
    filter!(((key, _),) -> key in commodities, macro_commodities)
    return macro_commodities
end

###### ###### ###### ######

function validate_commodities(
    commodities,
    macro_commodities::Dict{Symbol,DataType} = commodity_types(MacroEnergy),
)
    if any(commodity -> commodity ∉ keys(macro_commodities), commodities)
        error("Unknown commodities: $(setdiff(commodities, keys(macro_commodities)))")
    end
    return nothing
end

function load_subcommodities_from_file(path::AbstractString=pwd())
    subcommodities_path = joinpath(path, "tmp","subcommodities.jl")
    if isfile(subcommodities_path)
        @info(" ++ Loading pre-defined user commodities")
        @debug(" -- Loading subcommodities from file $(subcommodities_path)")
        include(subcommodities_path)
    end
    return subcommodities_path
end