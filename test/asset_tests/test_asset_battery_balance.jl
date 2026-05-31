module TestAssetBatteryBalance

using Test
using JuMP
using MacroEnergy

include("asset_test_utilities.jl")
using .AssetTestUtilities

import MacroEnergy:
    Battery,
    Electricity,
    flow,
    make,
    storage_level

function make_battery_case()
    system = make_test_system([Electricity])
    elec_timedata = system.time_data[:Electricity]

    source = make_supply_node(Electricity, :battery_source, elec_timedata, [1.0, 10.0, 2.0])
    sink = make_demand_node(Electricity, :battery_sink, elec_timedata, [0.0, 4.0, 0.0])
    push_locations!(system, source, sink)

    asset = make(
        Battery,
        Dict{Symbol,Any}(
            :id => :battery_test,
            :storage_can_expand => false,
            :storage_can_retire => false,
            :discharge_can_expand => false,
            :discharge_can_retire => false,
            :charge_can_expand => false,
            :charge_can_retire => false,
            :storage_existing_capacity => 10.0,
            :discharge_existing_capacity => 10.0,
            :charge_existing_capacity => 10.0,
            :charge_efficiency => 0.8,
            :discharge_efficiency => 0.5,
            :charge_start_vertex => :battery_source,
            :discharge_end_vertex => :battery_sink,
        ),
        system,
    )
    push!(system.assets, asset)

    return (; system, asset)
end

function assert_battery_solution(asset, model)
    expected_charge = [10.0, 0.0, 0.0]
    expected_discharge = [0.0, 4.0, 0.0]
    expected_storage = [8.0, 0.0, 0.0]

    @test objective_value(model) ≈ 10.0 atol = 1e-8
    for t in 1:3
        @test value(flow(asset.charge_edge, t)) ≈ expected_charge[t] atol = 1e-8
        @test value(flow(asset.discharge_edge, t)) ≈ expected_discharge[t] atol = 1e-8
        @test value(storage_level(asset.battery_storage, t)) ≈ expected_storage[t] atol = 1e-8
    end
end

function test_asset_battery_balance()
    @testset "Battery Small Solve Case" begin
        battery_case = make_battery_case()
        battery_model = build_test_model(battery_case.system)

        assert_battery_solution(battery_case.asset, battery_model)
    end

    return nothing
end

test_asset_battery_balance()

end # module TestAssetBatteryBalance
