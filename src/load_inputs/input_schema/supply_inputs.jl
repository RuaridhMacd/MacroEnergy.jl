"""
     check_and_convert_supply!(data)

Normalize node supply inputs into a consistent segmented representation:

`price_supply::OrderedDict{Symbol,Vector{Float64}}`
`max_supply::OrderedDict{Symbol,Vector{Float64}}`
`supply_segment_names::Vector{Symbol}`

Ideally, users should provide the inputs as dictionaries with segment names and single values or time series of values.
For example:
```julia
price_supply = OrderedDict(:cheap => [1.0, 1.5], :expensive => [4.0, 6.0])
max_supply = OrderedDict(:cheap => 15.0, :expensive => 5.0)
supply_segment_names = [:cheap, :expensive]
```

However, MacroEnergy will support a variety of alternative formats for user convenience. These include:
1. Two vectors:
```julia
price_supply = [1.0, 4.0]
max_supply = [15.0, 5.0]
supply_segment_names = [:cheap, :expensive] # optional, will default to seg1, seg2, etc. if not provided
```
This will be converted to:
```julia
price_supply = OrderedDict(:cheap => [1.0], :expensive => [4.0])
max_supply = OrderedDict(:cheap => [15.0], :expensive => [5.0])
supply_segment_names = [:cheap, :expensive]
```
2. A vector or single-segment dictionary for price_supply with no max_supply:
```julia
price_supply = [1.0, 1.5] # or price_supply = OrderedDict(:gas => [1.0, 1.5])
```
This will be converted to:
```julia
price_supply = OrderedDict(:seg1 => [1.0, 1.5]) 
max_supply = OrderedDict(:seg1 => [Inf])
supply_segment_names = [:seg1] # or [:gas] if the original price_supply was a single-segment dictionary with the name "gas"
```

3. A mix of vector and dictionary inputs:
```julia
price_supply = [1.0, 1.5]
max_supply = OrderedDict(:cheap => 15.0, :expensive => 5.0)
supply_segment_names = [:cheap, :expensive]
```
This will be converted to:
```julia
price_supply = OrderedDict(:cheap => [1.0], :expensive => [1.5])
max_supply = OrderedDict(:cheap => [15.0], :expensive => [5.0])
supply_segment_names = [:cheap, :expensive]
```
Alternatively, the max_supply may be a vector and price_supply a dictionary:
```julia
price_supply = OrderedDict(:cheap => [1.0], :expensive => [1.5])
max_supply = [15.0, 5.0]
supply_segment_names = [:cheap, :expensive]
```
This will be converted to:
```julia
price_supply = OrderedDict(:cheap => [1.0], :expensive => [1.5])
max_supply = OrderedDict(:cheap => [15.0], :expensive => [5.0])
supply_segment_names = [:cheap, :expensive]
```

4. Just a price_supply vector with no max_supply:
```julia
price_supply = [1.0, 1.5]
```
This will be converted to:
```julia
price_supply = OrderedDict(:seg1 => [1.0, 1.5])
max_supply = OrderedDict(:seg1 => [Inf])
supply_segment_names = [:seg1]
```

The function will throw errors for unsupported formats, such as mismatched lengths of vectors, or if there are multiple price segments but no max_supply provided.
"""
function check_and_convert_supply!(data)
    # We'll convert inputs to nothing if they're empty,
    # making it easier to parse by type
    price_supply = asnothing(data[:price_supply])
    max_supply = asnothing(get(data, :max_supply, nothing))
    supply_segment_names = asnothing(get(data, :supply_segment_names, nothing))

    if isnothing(price_supply)
        # If not prices are supplied, we return empty inputs.
        data[:price_supply] = OrderedDict{Symbol,Vector{Float64}}()
        data[:max_supply] = OrderedDict{Symbol,Vector{Float64}}()
        data[:supply_segment_names] = Symbol[]
        return nothing
    end

    supply_segment_names = parse_supply_names(price_supply, max_supply, supply_segment_names)
    price_supply, max_supply, supply_segment_names = parse_supply(price_supply, max_supply, supply_segment_names)

    data[:price_supply] = price_supply
    data[:max_supply] = max_supply
    data[:supply_segment_names] = supply_segment_names
    return nothing
end

function parse_supply_names(price_supply, max_supply, supply_segment_names)
    if price_supply isa AbstractDict
        return collect(Symbol.(keys(price_supply)))
    elseif max_supply isa AbstractDict
        return collect(Symbol.(keys(max_supply)))
    elseif supply_segment_names !== nothing
        return collect(Symbol.(supply_segment_names))
    elseif max_supply isa AbstractVector
        return default_segment_names(length(max_supply))
    else
        return default_segment_names(1)
    end
end

function parse_supply(price_supply, max_supply::Nothing, supply_segment_names::Vector{Symbol})
    if length(supply_segment_names) != 1
        throw(ArgumentError("If max_supply is not defined then exactly one supply segment name must be supplied or inferred. Current input is: $(supply_segment_names)"))
    end
    segment_name = supply_segment_names[1]
    if !(isa(price_supply, AbstractDict) || isa(price_supply, AbstractVector))
        throw(ArgumentError("price_supply must be either a vector or a dictionary. Current input is: $(typeof(price_supply))"))
    end
    if isa(price_supply, AbstractVector) || isa(price_supply, Number)
        price_supply_dict = OrderedDict{Symbol,Vector{Float64}}(
            segment_name => as_vector(price_supply)
        )
    elseif isa(price_supply, AbstractDict) && length(price_supply) == 1
        price_supply_dict = OrderedDict{Symbol,Vector{Float64}}(
            k => as_vector(v) for (k, v) in price_supply
        )
    else
        throw(ArgumentError("If max_supply is not defined then we will assume that the supply has only one segment. In that case, the price_supply must be either a vector or a single-segment dictionary. Define more segment maxes if needed. Current input is: $(typeof(price_supply))"))
    end
    return (
        price_supply_dict,
        OrderedDict{Symbol,Vector{Float64}}(
            segment_name => Float64[Inf]
        ),
        [segment_name]
    )
end

function parse_supply(price_supply::AbstractVector, max_supply::AbstractVector, supply_segment_names::Vector{Symbol})
    if length(price_supply) != length(max_supply)
        throw(ArgumentError("Length of price_supply vector must match length of max_supply vector. Current inputs are $(price_supply) and $(max_supply)"))
    end
    # Convert each entry in price_supply and max_supply into a segment with the name in supply_segment_names
    price_supply_dict = OrderedDict{Symbol,Vector{Float64}}()
    max_supply_dict = OrderedDict{Symbol,Vector{Float64}}()
    # Make sure supply_segment_names is the same length as price_supply, fill with default names if not provided, trim if too long
    if length(supply_segment_names) < length(price_supply)
        supply_segment_names = vcat(supply_segment_names, default_segment_names(length(price_supply) - length(supply_segment_names)))
    elseif length(supply_segment_names) > length(price_supply)
        supply_segment_names = supply_segment_names[1:length(price_supply)]
    end
    for (i, segment_name) in enumerate(supply_segment_names)
        price_supply_dict[segment_name] = as_vector(price_supply[i])
        max_supply_dict[segment_name] = as_vector(max_supply[i])
    end
    return price_supply_dict, max_supply_dict, supply_segment_names
end

function parse_supply(price_supply::AbstractVector, max_supply::AbstractDict, supply_segment_names::Vector{Symbol})
    if length(price_supply) != length(max_supply)
        throw(ArgumentError("Length of price_supply vector must match length of max_supply vector. Current inputs are $(price_supply) and $(max_supply)"))
    end
    # Use the entries in price_supply as the price for each segment
    price_supply_dict = OrderedDict{Symbol,Vector{Float64}}()
    for (i, segment_name) in enumerate(supply_segment_names)
        price_supply_dict[segment_name] = as_vector(price_supply[i])
    end
    # Make sure that max_supply is formatted correctly
    max_supply_dict = OrderedDict{Symbol,Vector{Float64}}()
    for (k, v) in max_supply
        if isa(v, Number) || isa(v, AbstractVector)
            max_supply_dict[k] = as_vector(v)
        else
            throw(ArgumentError("max_supply values must be either numbers or vectors. Current input for segment $(k) is: $(typeof(v))"))
        end
    end
    return price_supply_dict, max_supply_dict, supply_segment_names
end

function parse_supply(price_supply::AbstractDict, max_supply::AbstractVector, supply_segment_names::Vector{Symbol})
    if length(price_supply) != length(max_supply)
        throw(ArgumentError("Length of price_supply vector must match length of max_supply vector. Current inputs are $(price_supply) and $(max_supply)"))
    end
    # Use the entries in max_supply as the maximum supply for each segment
    max_supply_dict = OrderedDict{Symbol,Vector{Float64}}()
    for (i, segment_name) in enumerate(supply_segment_names)
        max_supply_dict[segment_name] = as_vector(max_supply[i])
    end
    return price_supply, max_supply_dict, supply_segment_names
end

function parse_supply(price_supply::AbstractDict, max_supply::AbstractDict, supply_segment_names::Vector{Symbol})
    if length(price_supply) != length(max_supply)
        throw(ArgumentError("Length of price_supply vector must match length of max_supply vector. Current inputs are $(price_supply) and $(max_supply)"))
    end
    price_supply_dict = OrderedDict{Symbol,Vector{Float64}}(
        k => as_vector(v) for (k, v) in price_supply
    )
    max_supply_dict = OrderedDict{Symbol,Vector{Float64}}(
        k => as_vector(v) for (k, v) in max_supply
    )
    return price_supply_dict, max_supply_dict, supply_segment_names
end