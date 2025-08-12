module MacroEnergyGurobiExt

using MacroEnergy
using Gurobi

function __init__()
    try
        MacroEnergy.set_opt_env!(:Gurobi, Gurobi.Env())
    catch e
        if isa(e, ErrorException) && occursin("Gurobi Error", string(e))
            @debug "Failed to initialize the Gurobi environment: $e"
        else
            rethrow(e)
        end
    end
end

end