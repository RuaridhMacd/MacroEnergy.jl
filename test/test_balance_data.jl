module TestBalanceData

using Test
using JuMP
using HiGHS
using MacroEnergy

const MOI = JuMP.MOI

import MacroEnergy:
    @add_balance_data,
    BalanceConstraint,
    BalanceData,
    Electricity,
    Node,
    Storage,
    TimeData,
    Transformation,
    UnidirectionalEdge,
    add_model_constraint!,
    balance_data,
    balance_sense,
    capacity,
    flow,
    get_balance,
    operation_model!,
    storage_level

function make_test_timedata()
    return TimeData{Electricity}(;
        time_interval = 1:1,
        hours_per_timestep = 1,
        period_index = 1,
        subperiods = [1:1],
        subperiod_indices = [1],
        subperiod_weights = Dict(1 => 1.0),
        subperiod_map = Dict(1 => 1),
    )
end

function make_test_storage(; id::Symbol = :test_storage, capacity_value::Float64 = 4.0)
    return Storage{Electricity}(;
        id = id,
        timedata = make_test_timedata(),
        capacity = capacity_value,
        balance_data = Dict(:storage => BalanceData()),
    )
end

function make_test_transformation_with_edges()
    timedata = make_test_timedata()

    input_node = Node{Electricity}(;
        id = :balance_input_node,
        timedata = timedata,
    )
    output_node = Node{Electricity}(;
        id = :balance_output_node,
        timedata = timedata,
    )
    transform = Transformation(;
        id = :balance_transform,
        timedata = timedata,
    )
    elec_edge = UnidirectionalEdge{Electricity}(;
        id = :balance_elec_edge,
        timedata = timedata,
        start_vertex = input_node,
        end_vertex = transform,
    )
    h2_edge = UnidirectionalEdge{Electricity}(;
        id = :balance_h2_edge,
        timedata = timedata,
        start_vertex = transform,
        end_vertex = output_node,
        capacity = 6.0,
    )

    return (; input_node, output_node, transform, elec_edge, h2_edge)
end

function find_term(data::BalanceData, obj, var::Symbol)
    return only(filter(term -> term.obj === obj && term.var == var, data.terms))
end

@testset "Balance Data" begin
    @testset "Legacy Dict Normalizes To BalanceData" begin
        transform = Transformation(;
            id = :legacy_transform,
            timedata = make_test_timedata(),
            balance_data = Dict(:energy => Dict(:edge_a => 2.0, :edge_b => -1.5)),
        )

        data = balance_data(transform, :energy)

        @test data isa BalanceData
        @test data.sense == :eq
        @test data.constant == 0.0
        @test length(data.terms) == 2

        terms = Dict(term.obj => term for term in data.terms)
        @test terms[:edge_a].var == :flow
        @test terms[:edge_a].coeff == 2.0
        @test terms[:edge_b].var == :flow
        @test terms[:edge_b].coeff == -1.5

        @test transform.balance_data[:energy] isa BalanceData
    end

    @testset "@add_balance_data Creates BalanceData" begin
        storage = make_test_storage(id = :macro_storage, capacity_value = 8.0)

        @add_balance_data(storage, :upper, storage_level(storage) <= capacity(storage))
        @add_balance_data(storage, :equal, storage_level(storage) == 0.5 * capacity(storage))
        @add_balance_data(storage, :lower, storage_level(storage) >= 0.25 * capacity(storage))

        upper = balance_data(storage, :upper)
        equal = balance_data(storage, :equal)
        lower = balance_data(storage, :lower)

        @test balance_sense(storage, :upper) == :le
        @test balance_sense(storage, :equal) == :eq
        @test balance_sense(storage, :lower) == :ge

        upper_terms = Dict(term.var => term for term in upper.terms)
        equal_terms = Dict(term.var => term for term in equal.terms)
        lower_terms = Dict(term.var => term for term in lower.terms)

        @test all(term.obj === storage for term in upper.terms)
        @test upper_terms[:storage_level].coeff == 1.0
        @test upper_terms[:capacity].coeff == -1.0

        @test all(term.obj === storage for term in equal.terms)
        @test equal_terms[:storage_level].coeff == 1.0
        @test equal_terms[:capacity].coeff == -0.5

        @test all(term.obj === storage for term in lower.terms)
        @test lower_terms[:storage_level].coeff == 1.0
        @test lower_terms[:capacity].coeff == -0.25
    end

    @testset "@add_balance_data Handles Mixed Flow And Capacity Terms" begin
        parts = make_test_transformation_with_edges()
        transform = parts.transform
        elec_edge = parts.elec_edge
        h2_edge = parts.h2_edge

        eff = 0.8
        area = 0.1

        @add_balance_data(
            transform,
            :ge_energy,
            flow(elec_edge) >= eff * flow(h2_edge) - area * capacity(h2_edge)
        )
        @add_balance_data(
            transform,
            :eq_energy,
            flow(elec_edge) == eff * flow(h2_edge) - area * capacity(h2_edge)
        )
        @add_balance_data(
            transform,
            :le_energy,
            flow(elec_edge) <= eff * flow(h2_edge) - area * capacity(h2_edge)
        )

        ge_data = balance_data(transform, :ge_energy)
        eq_data = balance_data(transform, :eq_energy)
        le_data = balance_data(transform, :le_energy)

        @test balance_sense(transform, :ge_energy) == :ge
        @test balance_sense(transform, :eq_energy) == :eq
        @test balance_sense(transform, :le_energy) == :le

        for data in (ge_data, eq_data, le_data)
            @test data.constant == 0.0
            @test find_term(data, elec_edge, :flow).coeff == 1.0
            @test find_term(data, h2_edge, :flow).coeff == -eff
            @test find_term(data, h2_edge, :capacity).coeff == area
        end

        model = Model(HiGHS.Optimizer)
        set_silent(model)
        model[:vREF] = @variable(model, base_name = "vREF")

        operation_model!(parts.input_node, model)
        operation_model!(parts.output_node, model)
        operation_model!(transform, model)
        operation_model!(elec_edge, model)
        operation_model!(h2_edge, model)

        ct = BalanceConstraint()
        add_model_constraint!(ct, transform, model)

        @test constraint_object(ct.constraint_ref[:ge_energy][1]).set isa MOI.GreaterThan{Float64}
        @test constraint_object(ct.constraint_ref[:eq_energy][1]).set isa MOI.EqualTo{Float64}
        @test constraint_object(ct.constraint_ref[:le_energy][1]).set isa MOI.LessThan{Float64}
    end

    @testset "Legacy Flow Balances Still Update Node Balance Expressions" begin
        timedata = make_test_timedata()

        start_node = Node{Electricity}(;
            id = :start_node,
            timedata = timedata,
        )
        end_node = Node{Electricity}(;
            id = :end_node,
            timedata = timedata,
            balance_data = Dict(:demand => Dict(:legacy_edge => 1.0)),
        )
        edge = UnidirectionalEdge{Electricity}(;
            id = :legacy_edge,
            timedata = timedata,
            start_vertex = start_node,
            end_vertex = end_node,
        )

        model = Model(HiGHS.Optimizer)
        set_silent(model)
        model[:vREF] = @variable(model, base_name = "vREF")

        operation_model!(start_node, model)
        operation_model!(end_node, model)
        operation_model!(edge, model)

        ct = BalanceConstraint()
        add_model_constraint!(ct, end_node, model)

        @objective(model, Max, flow(edge, 1))
        optimize!(model)

        @test is_solved_and_feasible(model)
        @test value(flow(edge, 1)) ≈ 0.0 atol = 1e-8
        @test value(get_balance(end_node, :demand, 1)) ≈ 0.0 atol = 1e-8
    end

    @testset "BalanceConstraint Honors Eq Le Ge Senses" begin
        storage = make_test_storage(id = :constraint_storage, capacity_value = 4.0)

        @add_balance_data(storage, :eq_balance, storage_level(storage) == 0.5 * capacity(storage))
        @add_balance_data(storage, :le_balance, storage_level(storage) <= 0.75 * capacity(storage))
        @add_balance_data(storage, :ge_balance, storage_level(storage) >= 0.25 * capacity(storage))

        model = Model(HiGHS.Optimizer)
        set_silent(model)
        model[:vREF] = @variable(model, base_name = "vREF")

        operation_model!(storage, model)

        ct = BalanceConstraint()
        add_model_constraint!(ct, storage, model)

        @test constraint_object(ct.constraint_ref[:eq_balance][1]).set isa MOI.EqualTo{Float64}
        @test constraint_object(ct.constraint_ref[:le_balance][1]).set isa MOI.LessThan{Float64}
        @test constraint_object(ct.constraint_ref[:ge_balance][1]).set isa MOI.GreaterThan{Float64}

        @objective(model, Max, storage_level(storage, 1))
        optimize!(model)

        @test is_solved_and_feasible(model)
        @test value(storage_level(storage, 1)) ≈ 2.0 atol = 1e-8
        @test value(get_balance(storage, :eq_balance, 1)) ≈ 0.0 atol = 1e-8
        @test value(get_balance(storage, :le_balance, 1)) <= 1e-8
        @test value(get_balance(storage, :ge_balance, 1)) >= -1e-8
    end
end

end
