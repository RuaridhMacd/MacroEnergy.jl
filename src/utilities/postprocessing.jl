function postprocess!(case::Case, solution::Model)
    for system in get_periods(case)
        postprocess!(system, solution)
    end
    return nothing
end

function postprocess!(system::System, solution::Model)
    # ToDo: we may want to add Nodes, Locations, etc. here too
    for asset in system.assets
        postprocess!(asset, solution)
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

function postprocess!(component::MacroObject, solution::Model)
    return nothing
end

function postprocess_asset!(asset::AbstractAsset, solution::Model)
    return nothing
end