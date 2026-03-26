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

    println("Updated node supply schema in $(file_path) and saved to $(destination)")
    println(" ++ This update script does not modify BalanceConstraint inputs. ++
    BalanceConstraint are now added to all Nodes by default.
    If you have an infinite sink (e.g. a co2_sink) or source (e.g. an uncosted fuel source), 
    then you must set constraints: {BalanceConstraint : false} in the input
    ")
    return destination
end

function update_node_supply_inputs(data::AbstractDict{Symbol,Any})
    if !haskey(data, :type) || !haskey(data, :instance_data)
        return data
    end

    if isa(data[:instance_data], AbstractDict{Symbol,Any})
        convert_node_supply_schema!(data[:instance_data])
    else
        convert_node_supply_schema!.(data[:instance_data])
    end

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
    convert_price_2_supply_schema!(data)

    if haskey(data, :supply) || haskey(data, :price_supply)
        check_and_convert_supply!(data)
        data[:supply] = prepare_to_json(data[:supply])
        remove_legacy_supply_schema!(data)
    end
    return nothing
end

function remove_legacy_supply_schema!(data::AbstractDict{Symbol,Any})
    for key in (:price_supply, :min_supply, :max_supply, :supply_segment_names)
        if haskey(data, key)
            delete!(data, key)
        end
    end
    return nothing
end

function convert_price_2_supply_schema!(data::AbstractDict{Symbol,Any}; max_print_length::Int=5)
    if haskey(data, :price)
        price_data = data[:price]
        if haskey(data, :price_supply) || haskey(data, :supply)
            if length(price_data) > max_print_length
                price_preview = string(price_data[1:max_print_length], "...")
            else
                price_preview = string(price_data)
            end
            @warn("Data has both :price and an existing supply schema. :price = $(price_preview). This entry will be skipped to avoid overwriting existing supply data.")
            return nothing
        end
        data[:supply] = OrderedDict(
            :seg1 => OrderedDict(
                :price => as_vector(data[:price]),
                :min => [0.0],
                :max => [Inf],
            ),
        )
        delete!(data, :price)
    end
    return nothing
end
