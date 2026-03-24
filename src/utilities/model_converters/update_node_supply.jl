function update_node_supply_inputs(
    file_path::AbstractString;
    output_path::Union{Nothing,AbstractString}=nothing,
)
    data = copy(read_json(file_path)) # This converts JSON3 -> Dict{Symbol,Any}
    if !isa(data, AbstractDict{Symbol,Any})
        throw(ArgumentError("Expected a JSON object at the top level of $(file_path)"))
    end

    # In theory, the Nodes file can have multiple entries
    for (group_name, node_group) in data
        data[group_name] = update_node_supply_inputs(node_group)
    end

    destination = isnothing(output_path) ? file_path : output_path
    write_json(destination, data)
    return destination
end

function update_node_supply_inputs(data::AbstractDict{Symbol,Any})
    if !haskey(data, :type) || !haskey(data, :instance_data)
        return nothing
    end
    convert_node_supply_schema!.(data[:instance_data])
    if haskey(data, :global_data)
        convert_node_supply_schema!(data[:global_data])
    end
    return data
end

function update_node_supply_inputs(data::Vector{Dict{Symbol,Any}})
    for (idx, node) in enumerate(data)
        if isa(node, AbstractDict{Symbol,Any})
            data[idx] = update_node_supply_inputs(node)
        end
    end
    return data
end

function update_node_supply_inputs(data)
    @warn("Unexpected data format for $(data). Skipping conversion.")
    return data
end

function convert_node_supply_schema!(data::AbstractDict{Symbol,Any})
    if haskey(data, :price_supply)
        check_and_convert_supply!(data)
    end
    convert_price_2_supply_schema!(data)
    return nothing
end

function convert_price_2_supply_schema!(data::AbstractDict{Symbol,Any}; max_print_length::Int=5)
    if haskey(data, :price)
        price_data = data[:price]
        if haskey(data, :price_supply)
            if length(price_data) > max_print_length
                price_preview = string(price_data[1:max_print_length], "...")
            else
                price_preview = string(price_data)
            end
            @warn("Data has both :price and :price_supply keys. :price = $(price_preview). This entry will be skipped to avoid overwriting existing :price_supply data.")
            return nothing
        end
            data[:price_supply] = OrderedDict(:seg1 => data[:price])
            data[:max_supply] = OrderedDict(:seg1 => [Inf])
            data[:supply_segment_names] = [:seg1]
            delete!(data, :price)
    end
    return nothing
end
