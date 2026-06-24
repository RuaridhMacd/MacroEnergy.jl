module TestInferredConstraints

using Test
using MacroEnergy

function inferred_constraints(data::Dict{Symbol,Any})
    MacroEnergy.infer_edge_constraints!(data)
    return data[:constraints]
end

function inferred_storage_constraints(data::Dict{Symbol,Any})
    MacroEnergy.infer_storage_constraints!(data)
    return data[:constraints]
end

@testset "Inferred Edge Constraints" begin
    @test MacroEnergy.has_ramping_input(Dict{Symbol,Any}(:ramp_up_fraction => 0.75))
    @test MacroEnergy.has_ramping_input(Dict{Symbol,Any}(:ramp_down_fraction => 0.5))
    @test !MacroEnergy.has_ramping_input(Dict{Symbol,Any}(:ramp_up_fraction => 1.0))

    inferred_data = Dict{Symbol,Any}(:ramp_up_fraction => 0.75)
    MacroEnergy.infer_edge_constraints!(inferred_data)
    @test inferred_data[:constraints][:RampingLimitConstraint]

    disabled_data = Dict{Symbol,Any}(
        :ramp_up_fraction => 0.75,
        :constraints => Dict{Symbol,Bool}(:RampingLimitConstraint => false),
    )
    MacroEnergy.infer_edge_constraints!(disabled_data)
    @test disabled_data[:constraints][:RampingLimitConstraint] == false

    nonbinding_data = Dict{Symbol,Any}(:ramp_up_fraction => 1.0, :ramp_down_fraction => 1.0)
    MacroEnergy.infer_edge_constraints!(nonbinding_data)
    @test !haskey(nonbinding_data[:constraints], :RampingLimitConstraint)

    @test inferred_constraints(Dict{Symbol,Any}(:min_flow_fraction => 0.2))[:MinFlowConstraint]
    bidirectional_minflow_data = Dict{Symbol,Any}(
        :unidirectional => false,
        :min_flow_fraction => 0.2,
    )
    @test !haskey(inferred_constraints(bidirectional_minflow_data), :MinFlowConstraint)

    @test inferred_constraints(Dict{Symbol,Any}(:has_capacity => true))[:CapacityConstraint]
    @test inferred_constraints(Dict{Symbol,Any}(:max_capacity => 100))[:MaxCapacityConstraint]
    @test inferred_constraints(Dict{Symbol,Any}(:max_capacity => 100.0))[:MaxCapacityConstraint]
    @test !haskey(inferred_constraints(Dict{Symbol,Any}(:max_capacity => "Inf")), :MaxCapacityConstraint)
    @test !haskey(inferred_constraints(Dict{Symbol,Any}(:max_capacity => Inf)), :MaxCapacityConstraint)

    @test inferred_constraints(Dict{Symbol,Any}(:min_capacity => 1.0))[:MinCapacityConstraint]
    @test inferred_constraints(Dict{Symbol,Any}(:max_new_capacity => 25))[:MaxNewCapacityConstraint]
    @test !haskey(
        inferred_constraints(Dict{Symbol,Any}(:max_new_capacity => "Inf")),
        :MaxNewCapacityConstraint,
    )

    @test inferred_constraints(
        Dict{Symbol,Any}(:uc => true, :min_up_time => 2),
    )[:MinUpTimeConstraint]
    @test inferred_constraints(
        Dict{Symbol,Any}(:uc => true, :min_down_time => 2),
    )[:MinDownTimeConstraint]
    @test !haskey(
        inferred_constraints(Dict{Symbol,Any}(:uc => false, :min_up_time => 2)),
        :MinUpTimeConstraint,
    )

    disabled_min_capacity_data = Dict{Symbol,Any}(
        :min_capacity => 1.0,
        :constraints => Dict{Symbol,Bool}(:MinCapacityConstraint => false),
    )
    @test inferred_constraints(disabled_min_capacity_data)[:MinCapacityConstraint] == false
end

@testset "Inferred Storage Constraints" begin
    @test inferred_storage_constraints(Dict{Symbol,Any}())[:StorageCapacityConstraint]

    disabled_storage_capacity_data = Dict{Symbol,Any}(
        :constraints => Dict{Symbol,Bool}(:StorageCapacityConstraint => false),
    )
    @test inferred_storage_constraints(disabled_storage_capacity_data)[:StorageCapacityConstraint] == false

    @test inferred_storage_constraints(
        Dict{Symbol,Any}(:max_capacity => 100),
    )[:MaxCapacityConstraint]
    @test inferred_storage_constraints(
        Dict{Symbol,Any}(:max_capacity => 100.0),
    )[:MaxCapacityConstraint]
    @test !haskey(
        inferred_storage_constraints(Dict{Symbol,Any}(:max_capacity => "Inf")),
        :MaxCapacityConstraint,
    )
    @test !haskey(
        inferred_storage_constraints(Dict{Symbol,Any}(:max_capacity => Inf)),
        :MaxCapacityConstraint,
    )

    @test inferred_storage_constraints(
        Dict{Symbol,Any}(:min_capacity => 1.0),
    )[:MinCapacityConstraint]
    @test inferred_storage_constraints(
        Dict{Symbol,Any}(:max_new_capacity => 25),
    )[:MaxNewCapacityConstraint]
    @test !haskey(
        inferred_storage_constraints(Dict{Symbol,Any}(:max_new_capacity => "Inf")),
        :MaxNewCapacityConstraint,
    )

    @test inferred_storage_constraints(
        Dict{Symbol,Any}(:max_duration => 10),
    )[:StorageMaxDurationConstraint]
    @test inferred_storage_constraints(
        Dict{Symbol,Any}(:max_duration => 10.0),
    )[:StorageMaxDurationConstraint]
    @test !haskey(
        inferred_storage_constraints(Dict{Symbol,Any}(:max_duration => "Inf")),
        :StorageMaxDurationConstraint,
    )
    @test !haskey(
        inferred_storage_constraints(Dict{Symbol,Any}(:max_duration => Inf)),
        :StorageMaxDurationConstraint,
    )
    @test inferred_storage_constraints(
        Dict{Symbol,Any}(:min_duration => 2.0),
    )[:StorageMinDurationConstraint]

    @test inferred_storage_constraints(
        Dict{Symbol,Any}(:max_storage_level => 0.9),
    )[:MaxStorageLevelConstraint]
    @test !haskey(
        inferred_storage_constraints(Dict{Symbol,Any}(:max_storage_level => 1.0)),
        :MaxStorageLevelConstraint,
    )
    @test inferred_storage_constraints(
        Dict{Symbol,Any}(:min_storage_level => 0.1),
    )[:MinStorageLevelConstraint]

    @test inferred_storage_constraints(
        Dict{Symbol,Any}(:charge_discharge_ratio => 1.0),
    )[:StorageChargeDischargeRatioConstraint]
    @test !haskey(
        inferred_storage_constraints(Dict{Symbol,Any}(:charge_discharge_ratio => 0.0)),
        :StorageChargeDischargeRatioConstraint,
    )

    @test inferred_storage_constraints(
        Dict{Symbol,Any}(:long_duration => true),
    )[:LongDurationStorageImplicitMinMaxConstraint]
    disabled_long_duration_data = Dict{Symbol,Any}(
        :long_duration => true,
        :constraints => Dict{Symbol,Bool}(:LongDurationStorageImplicitMinMaxConstraint => false),
    )
    @test inferred_storage_constraints(disabled_long_duration_data)[:LongDurationStorageImplicitMinMaxConstraint] == false

    disabled_min_level_data = Dict{Symbol,Any}(
        :min_storage_level => 0.1,
        :constraints => Dict{Symbol,Bool}(:MinStorageLevelConstraint => false),
    )
    @test inferred_storage_constraints(disabled_min_level_data)[:MinStorageLevelConstraint] == false
end

end
