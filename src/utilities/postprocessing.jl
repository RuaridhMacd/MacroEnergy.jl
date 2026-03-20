function postprocess!(case::Case, solution::Model)
    for system in get_periods(case)
        postprocess!(system, solution)
    end
    return nothing
end

function postprocess!(system::System, solution::Model)
    for asset in system.assets
        postprocess!(asset, solution)
    end

    for location in system.locations
        postprocess!(location, solution)
    end

    return nothing
end

function postprocess!(asset::AbstractAsset, solution::Model)
    for field_name in fieldnames(typeof(asset))
        component = getfield(asset, field_name)
        if isa(component, MacroObject)
            postprocess!(component, solution)
        end
    end

    postprocess_asset!(asset, solution)
    return nothing
end

function postprocess!(n::Node, solution::Model)
    time_steps = collect(time_interval(n))
    effective_price = zeros(Float64, isempty(time_steps) ? 0 : maximum(time_steps))

    if all(iszero, max_supply(n)) || isempty(supply_flow(n))
        n.price = effective_price
        return nothing
    end

    for t in time_steps
        total_supply = 0.0
        total_cost = 0.0

        for s in supply_segments(n)
            supplied = value(supply_flow(n, s, t))
            total_supply += supplied
            total_cost += price_supply(n, s) * supplied
        end

        effective_price[t] = iszero(total_supply) ? 0.0 : total_cost / total_supply
    end

    n.price = effective_price
    return nothing
end

function postprocess!(component::MacroObject, solution::Model)
    return nothing
end

function postprocess_asset!(asset::AbstractAsset, solution::Model)
    return nothing
end