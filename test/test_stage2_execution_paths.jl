module TestStage2ExecutionPaths

using Test
using HiGHS
using JuMP
using JSON3
using MacroEnergy

import MacroEnergy:
    Myopic,
    build_monolithic_model,
    build_monolithic_problem_instances,
    build_problem_instance,
    create_optimizer,
    create_problem_model,
    load_case,
    populate_problem_model!,
    solution_algorithm

const FIXTURE_CASE_DIR = joinpath(@__DIR__, "test_small_case")

function with_temp_case(f::Function, case_settings::AbstractDict)
    mktempdir() do temp_dir
        case_dir = joinpath(temp_dir, "case")
        cp(FIXTURE_CASE_DIR, case_dir; force=true)
        period_lengths = get(case_settings, "PeriodLengths", [1])
        system_data_path = joinpath(case_dir, "system_data.json")
        if length(period_lengths) > 1
            fixture_case_data = JSON3.read(read(system_data_path, String), Dict{String,Any})
            first_system = fixture_case_data["case"][1]
            fixture_case_data["case"] = [deepcopy(first_system) for _ in eachindex(period_lengths)]
            write(system_data_path, JSON3.write(fixture_case_data))
        end
        settings_path = joinpath(case_dir, "settings", "case_settings.json")
        write(settings_path, JSON3.write(case_settings))
        return f(case_dir)
    end
end

function test_monolithic_multi_period_build()
    case_settings = Dict(
        "SolutionAlgorithm" => "Monolithic",
        "PeriodLengths" => [1, 1],
        "DiscountRate" => 0.045,
    )

    with_temp_case(case_settings) do case_dir
        case = load_case(case_dir)
        optimizer = create_optimizer(HiGHS.Optimizer)
        instances = build_monolithic_problem_instances(case)
        model = build_monolithic_model(case, optimizer)

        @test length(case.systems) == 2
        @test length(instances) == 2
        @test JuMP.num_variables(model) > 0
        @test JuMP.num_constraints(model; count_variable_in_set_constraints=false) > 0
    end

    return nothing
end

function test_myopic_multi_period_builder_path()
    case_settings = Dict(
        "SolutionAlgorithm" => "Myopic",
        "PeriodLengths" => [1, 1],
        "DiscountRate" => 0.045,
        "MyopicSettings" => Dict(
            "ReturnModels" => true,
            "WriteModelLP" => false,
            "Restart" => Dict(
                "enabled" => false,
                "folder" => "results_001",
                "from_period" => 1,
            ),
            "StopAfterPeriod" => 2,
        ),
    )

    with_temp_case(case_settings) do case_dir
        case = load_case(case_dir)
        optimizer = create_optimizer(HiGHS.Optimizer)
        instance = build_problem_instance(case.systems[1], nothing; id=:myopic_period_1)
        model = create_problem_model(instance, optimizer)

        @variable(model, vREF == 1)
        model[:eFixedCost] = AffExpr(0.0)
        model[:eInvestmentFixedCost] = AffExpr(0.0)
        model[:eOMFixedCost] = AffExpr(0.0)
        model[:eVariableCost] = AffExpr(0.0)
        populate_problem_model!(instance, model; period_idx=1)

        @test length(case.systems) == 2
        @test solution_algorithm(case) isa Myopic
        @test JuMP.num_variables(model) > 0
        @test JuMP.num_constraints(model; count_variable_in_set_constraints=false) > 0
    end

    return nothing
end

@testset "Stage 2 Execution Paths" begin
    test_monolithic_multi_period_build()
    test_myopic_multi_period_builder_path()
end

end # module TestStage2ExecutionPaths
