module TestMultiPeriodMonolithicRegression

using CSV
using DataFrames
using HiGHS
using Test
using MacroEnergy

import MacroEnergy:
    MyopicResults,
    Problem,
    run_case

const MONOLITHIC_CASE_SOURCE = joinpath(@__DIR__, "test_multiperiod_small_case_monolithic")
const MYOPIC_CASE_SOURCE = joinpath(@__DIR__, "test_multiperiod_small_case_myopic")
const TOL = 1.0e-6

function result_number(name::AbstractString)
    m = match(r"^results_(\d+)$", name)
    return isnothing(m) ? nothing : parse(Int, m.captures[1])
end

function latest_results_path(case_path::AbstractString)
    results = Pair{Int,String}[]
    for name in readdir(case_path)
        number = result_number(name)
        isnothing(number) && continue
        push!(results, number => joinpath(case_path, name))
    end

    @assert !isempty(results)
    return last(sort(results; by=first)).second
end

function copy_case_to_temp(case_source::AbstractString)
    temp_dir = mktempdir()
    case_path = joinpath(temp_dir, basename(case_source))
    cp(case_source, case_path)
    return temp_dir, case_path
end

function copy_multiperiod_fixtures_to_temp(case_source::AbstractString)
    temp_dir = mktempdir()
    cp(MONOLITHIC_CASE_SOURCE, joinpath(temp_dir, basename(MONOLITHIC_CASE_SOURCE)))
    cp(MYOPIC_CASE_SOURCE, joinpath(temp_dir, basename(MYOPIC_CASE_SOURCE)))
    return temp_dir, joinpath(temp_dir, basename(case_source))
end

function numeric_value(df::DataFrame, id_column::Symbol, id_value::AbstractString, value_column::Symbol)
    row = only(findall(df[!, id_column] .== id_value))
    return Float64(df[row, value_column])
end

function wide_value(df::DataFrame, column::AbstractString)
    @test nrow(df) == 1
    @test column in names(df)
    return Float64(df[1, column])
end

function max_abs_diff(path::AbstractString, expected::Dict{String,Float64})
    df = CSV.read(path, DataFrame)
    return maximum(expected; init=0.0) do (column, value)
        abs(wide_value(df, column) - value)
    end
end

function assert_period_outputs(result_path::AbstractString, period::Int; demand::Float64, new_capacity::Float64, existing_capacity::Float64)
    period_path = joinpath(result_path, "results_period_$(period)")
    capacity = CSV.read(joinpath(period_path, "capacity.csv"), DataFrame)
    vre_capacity = numeric_value(capacity, :component_id, "cheap_vre_edge", :capacity)
    vre_new_capacity = numeric_value(capacity, :component_id, "cheap_vre_edge", :new_capacity)
    vre_existing_capacity = numeric_value(capacity, :component_id, "cheap_vre_edge", :existing_capacity)

    @test vre_capacity ≈ demand atol=TOL
    @test vre_new_capacity ≈ new_capacity atol=TOL
    @test vre_existing_capacity ≈ existing_capacity atol=TOL

    flow_diff = max_abs_diff(
        joinpath(period_path, "flows.csv"),
        Dict(
            "cheap_vre_edge" => demand,
            "test_battery_charge_edge" => 0.0,
            "test_battery_discharge_edge" => 0.0,
        ),
    )
    storage_diff = max_abs_diff(
        joinpath(period_path, "storage_level.csv"),
        Dict("test_battery_storage" => 0.0),
    )
    nsd_diff = max_abs_diff(
        joinpath(period_path, "non_served_demand.csv"),
        Dict("elec_seg1" => 0.0),
    )

    @test flow_diff <= TOL
    @test storage_diff <= TOL
    @test nsd_diff <= TOL

    return nothing
end

@testset "Small multi-period monolithic regression" begin
    temp_dir, case_path = copy_case_to_temp(MONOLITHIC_CASE_SOURCE)
    try
        systems, problem = run_case(
            case_path;
            optimizer=HiGHS.Optimizer,
            optimizer_attributes=("solver" => "ipm", "run_crossover" => "on"),
            log_to_console=false,
            log_to_file=false,
        )

        @test problem isa Problem
        @test length(systems) == 2

        result_path = latest_results_path(case_path)

        assert_period_outputs(result_path, 1; demand=10.0, new_capacity=10.0, existing_capacity=0.0)
        assert_period_outputs(result_path, 2; demand=15.0, new_capacity=5.0, existing_capacity=10.0)
    finally
        rm(temp_dir; recursive=true, force=true)
    end
end

function write_myopic_return_models_settings!(case_path::AbstractString)
    write(
        joinpath(case_path, "settings", "case_settings.json"),
        """
        {
            "PeriodLengths": [1, 1],
            "DiscountRate": 0.05,
            "SolutionAlgorithm": "Monolithic",
            "ExpansionHorizon": "Myopic",
            "MyopicSettings": {
                "ReturnModels": true,
                "WriteModelLP": false
            }
        }
        """,
    )
    return nothing
end

function run_small_myopic_case(case_path::AbstractString)
    return run_case(
        case_path;
        optimizer=HiGHS.Optimizer,
        optimizer_attributes=("solver" => "ipm", "run_crossover" => "on"),
        log_to_console=false,
        log_to_file=false,
    )
end

@testset "Small multi-period Myopic regression" begin
    temp_dir, case_path = copy_multiperiod_fixtures_to_temp(MYOPIC_CASE_SOURCE)
    try
        systems, results = run_small_myopic_case(case_path)

        @test results isa MyopicResults
        @test isnothing(results.results)
        @test length(systems) == 2

        result_path = latest_results_path(case_path)

        assert_period_outputs(result_path, 1; demand=10.0, new_capacity=10.0, existing_capacity=0.0)
        assert_period_outputs(result_path, 2; demand=15.0, new_capacity=5.0, existing_capacity=10.0)
    finally
        rm(temp_dir; recursive=true, force=true)
    end
end

@testset "Small multi-period Myopic ReturnModels" begin
    temp_dir, case_path = copy_multiperiod_fixtures_to_temp(MYOPIC_CASE_SOURCE)
    try
        write_myopic_return_models_settings!(case_path)
        systems, results = run_small_myopic_case(case_path)

        @test results isa MyopicResults
        @test length(systems) == 2
        @test length(results.results) == 2
        @test all(result -> result isa Problem, results.results)
    finally
        rm(temp_dir; recursive=true, force=true)
    end
end

end
