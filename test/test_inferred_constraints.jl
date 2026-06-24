module TestInferredConstraints

using Test
using MacroEnergy

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
end

end
