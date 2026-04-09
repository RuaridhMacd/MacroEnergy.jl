module TestBalanceData

using Test
using JuMP
using HiGHS
using MacroEnergy

const MOI = JuMP.MOI

import MacroEnergy:
    @add_balance,
    @add_stoichiometric_balance,
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

function make_test_timedata(num_steps::Int = 1)
    return TimeData{Electricity}(;
        time_interval = 1:num_steps,
        hours_per_timestep = 1,
        period_index = 1,
        subperiods = [1:num_steps],
        subperiod_indices = [1],
        subperiod_weights = Dict(1 => 1.0),
        subperiod_map = Dict(1 => 1),
    )
end

function make_test_storage(;
    id::Symbol = :test_storage,
    capacity_value::Float64 = 4.0,
    num_steps::Int = 1,
)
    return Storage{Electricity}(;
        id = id,
        timedata = make_test_timedata(num_steps),
        capacity = capacity_value,
        balance_data = Dict(:storage => BalanceData()),
    )
end

function make_test_transformation_with_edges(num_steps::Int = 1)
    timedata = make_test_timedata(num_steps)

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
        capacity = 6.0,
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

function make_test_transformation_with_four_edges(num_steps::Int = 1)
    timedata = make_test_timedata(num_steps)

    input_node_1 = Node{Electricity}(;
        id = :balance_input_node_1,
        timedata = timedata,
    )
    input_node_2 = Node{Electricity}(;
        id = :balance_input_node_2,
        timedata = timedata,
    )
    output_node_1 = Node{Electricity}(;
        id = :balance_output_node_1,
        timedata = timedata,
    )
    output_node_2 = Node{Electricity}(;
        id = :balance_output_node_2,
        timedata = timedata,
    )
    transform = Transformation(;
        id = :balance_transform_four_edges,
        timedata = timedata,
    )
    elec_edge = UnidirectionalEdge{Electricity}(;
        id = :balance_elec_edge_four,
        timedata = timedata,
        start_vertex = input_node_1,
        end_vertex = transform,
        capacity = 6.0,
    )
    water_edge = UnidirectionalEdge{Electricity}(;
        id = :balance_water_edge_four,
        timedata = timedata,
        start_vertex = input_node_2,
        end_vertex = transform,
        capacity = 6.0,
    )
    h2_edge = UnidirectionalEdge{Electricity}(;
        id = :balance_h2_edge_four,
        timedata = timedata,
        start_vertex = transform,
        end_vertex = output_node_1,
        capacity = 6.0,
    )
    co2_edge = UnidirectionalEdge{Electricity}(;
        id = :balance_co2_edge_four,
        timedata = timedata,
        start_vertex = transform,
        end_vertex = output_node_2,
        capacity = 6.0,
    )

    return (; input_node_1, input_node_2, output_node_1, output_node_2, transform, elec_edge, water_edge, h2_edge, co2_edge)
end

function make_test_storage_with_edges(num_steps::Int = 1)
    timedata = make_test_timedata(num_steps)

    start_node = Node{Electricity}(;
        id = :storage_input_node,
        timedata = timedata,
    )
    end_node = Node{Electricity}(;
        id = :storage_output_node,
        timedata = timedata,
    )
    storage = Storage{Electricity}(;
        id = :balance_storage,
        timedata = timedata,
        capacity = 4.0,
        balance_data = Dict(:storage => BalanceData()),
    )
    charge_edge = UnidirectionalEdge{Electricity}(;
        id = :storage_charge_edge,
        timedata = timedata,
        start_vertex = start_node,
        end_vertex = storage,
        capacity = 6.0,
    )
    discharge_edge = UnidirectionalEdge{Electricity}(;
        id = :storage_discharge_edge,
        timedata = timedata,
        start_vertex = storage,
        end_vertex = end_node,
        capacity = 6.0,
    )

    return (; start_node, end_node, storage, charge_edge, discharge_edge)
end

function find_term(data::BalanceData, obj, var::Symbol)
    return only(filter(term -> term.obj === obj && term.var == var, data.terms))
end

function balance_signature(data::BalanceData)
    terms = Dict((term.obj, term.var) => term.coeff for term in data.terms)
    return (sense = data.sense, constant = data.constant, terms = terms)
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

    @testset "@add_balance Creates BalanceData" begin
        storage = make_test_storage(id = :macro_storage, capacity_value = 8.0)

        @add_balance(storage, :upper, storage_level(storage) <= capacity(storage))
        @add_balance(storage, :equal, storage_level(storage) == 0.5 * capacity(storage))
        @add_balance(storage, :lower, storage_level(storage) >= 0.25 * capacity(storage))

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

    @testset "@add_balance Normalizes Scalar And Vector Coefficients" begin
        parts = make_test_transformation_with_edges(3)
        transform = parts.transform
        elec_edge = parts.elec_edge
        h2_edge = parts.h2_edge

        scalar_eff = 0.8
        singleton_eff = [0.7]
        profile_eff = [0.6, 0.7, 0.8]

        @add_balance(
            transform,
            :scalar_energy,
            flow(elec_edge) == scalar_eff * flow(h2_edge)
        )
        @add_balance(
            transform,
            :singleton_energy,
            flow(elec_edge) == singleton_eff * flow(h2_edge)
        )
        @add_balance(
            transform,
            :profile_energy,
            flow(elec_edge) == profile_eff * flow(h2_edge)
        )

        scalar_term = find_term(balance_data(transform, :scalar_energy), h2_edge, :flow)
        singleton_term = find_term(balance_data(transform, :singleton_energy), h2_edge, :flow)
        profile_term = find_term(balance_data(transform, :profile_energy), h2_edge, :flow)

        @test scalar_term.coeff == -scalar_eff
        @test singleton_term.coeff == -only(singleton_eff)
        @test profile_term.coeff == -profile_eff
    end

    @testset "@add_balance Handles Mixed Flow And Capacity Terms" begin
        parts = make_test_transformation_with_edges()
        transform = parts.transform
        elec_edge = parts.elec_edge
        h2_edge = parts.h2_edge

        eff = 0.8
        area = 0.1

        @add_balance(
            transform,
            :ge_energy,
            flow(elec_edge) >= eff * flow(h2_edge) - area * capacity(h2_edge)
        )
        @add_balance(
            transform,
            :eq_energy,
            flow(elec_edge) == eff * flow(h2_edge) - area * capacity(h2_edge)
        )
        @add_balance(
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

    @testset "@add_stoichiometric_balance Expands Multiple Inputs To Pairwise Balances" begin
        parts = make_test_transformation_with_four_edges()
        transform = parts.transform
        elec_edge = parts.elec_edge
        water_edge = parts.water_edge
        h2_edge = parts.h2_edge

        efficiency_rate = 0.8
        water_consumption = 0.3

        @add_stoichiometric_balance(
            transform,
            :energy,
            efficiency_rate * flow(elec_edge) + water_consumption * flow(water_edge) --> flow(h2_edge),
            flow(h2_edge),
        )

        @add_balance(
            transform,
            :expected_1,
            flow(h2_edge) + efficiency_rate * flow(elec_edge) == 0.0,
        )
        @add_balance(
            transform,
            :expected_2,
            flow(h2_edge) + water_consumption * flow(water_edge) == 0.0,
        )

        @test balance_signature(balance_data(transform, :energy_1)) ==
              balance_signature(balance_data(transform, :expected_1))
        @test balance_signature(balance_data(transform, :energy_2)) ==
              balance_signature(balance_data(transform, :expected_2))
    end

    @testset "@add_stoichiometric_balance Expands Mixed-Side Outputs Around Base Term" begin
        parts = make_test_transformation_with_four_edges()
        transform = parts.transform
        elec_edge = parts.elec_edge
        h2_edge = parts.h2_edge
        co2_edge = parts.co2_edge

        fuel_consumption = 1.7
        emission_rate = 0.2

        @add_stoichiometric_balance(
            transform,
            :conversion,
            fuel_consumption * flow(elec_edge) --> flow(h2_edge) + emission_rate * flow(co2_edge),
            flow(h2_edge),
        )

        @add_balance(
            transform,
            :expected_1,
            flow(h2_edge) + fuel_consumption * flow(elec_edge) == 0.0,
        )
        @add_balance(
            transform,
            :expected_2,
            emission_rate * flow(h2_edge) - flow(co2_edge) == 0.0,
        )

        @test balance_signature(balance_data(transform, :conversion_1)) ==
              balance_signature(balance_data(transform, :expected_1))
        @test balance_signature(balance_data(transform, :conversion_2)) ==
              balance_signature(balance_data(transform, :expected_2))
    end

    @testset "@add_stoichiometric_balance Handles Input-Side Base Term With Outputs" begin
        parts = make_test_transformation_with_four_edges()
        transform = parts.transform
        elec_edge = parts.elec_edge
        h2_edge = parts.h2_edge
        co2_edge = parts.co2_edge

        hydrogen_production = 1.7
        emission_rate = 0.2

        @add_stoichiometric_balance(
            transform,
            :beccs_style,
            flow(elec_edge) --> hydrogen_production * flow(h2_edge) + emission_rate * flow(co2_edge),
            flow(elec_edge),
        )

        @add_balance(
            transform,
            :expected_1,
            hydrogen_production * flow(elec_edge) + flow(h2_edge) == 0.0,
        )
        @add_balance(
            transform,
            :expected_2,
            emission_rate * flow(elec_edge) + flow(co2_edge) == 0.0,
        )

        @test balance_signature(balance_data(transform, :beccs_style_1)) ==
              balance_signature(balance_data(transform, :expected_1))
        @test balance_signature(balance_data(transform, :beccs_style_2)) ==
              balance_signature(balance_data(transform, :expected_2))
    end

    @testset "@add_stoichiometric_balance Rejects Negative Terms And Constants" begin
        @test_throws ErrorException macroexpand(
            @__MODULE__,
            :(
                @add_stoichiometric_balance(
                    x,
                    :bad_unary,
                    -flow(e1) --> flow(e2),
                    flow(e2),
                )
            ),
        )

        @test_throws ErrorException macroexpand(
            @__MODULE__,
            :(
                @add_stoichiometric_balance(
                    x,
                    :bad_binary,
                    flow(e1) - flow(e2) --> flow(e3),
                    flow(e3),
                )
            ),
        )

        @test_throws ErrorException macroexpand(
            @__MODULE__,
            :(
                @add_stoichiometric_balance(
                    x,
                    :bad_constant,
                    flow(e1) + 3 --> flow(e2),
                    flow(e2),
                )
            ),
        )
    end

    @testset "Edge balance_data Supports Time-Varying Coefficients" begin
        parts = make_test_storage_with_edges(3)
        storage = parts.storage
        charge_edge = parts.charge_edge
        discharge_edge = parts.discharge_edge

        charge_eff = [0.5, 0.6, 0.7]
        discharge_eff = 1.25

        @add_balance(
            storage,
            :storage,
            discharge_eff * flow(discharge_edge) + charge_eff * flow(charge_edge) == 0.0
        )

        @test_throws ErrorException balance_data(charge_edge, storage, :storage)

        @test balance_data(charge_edge, storage, :storage, 1) == charge_eff[1]
        @test balance_data(charge_edge, storage, :storage, 2) == charge_eff[2]
        @test balance_data(charge_edge, storage, :storage, 3) == charge_eff[3]

        @test balance_data(discharge_edge, storage, :storage) == discharge_eff
        @test balance_data(discharge_edge, storage, :storage, 1) == discharge_eff
        @test balance_data(discharge_edge, storage, :storage, 2) == discharge_eff
        @test balance_data(discharge_edge, storage, :storage, 3) == discharge_eff
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

    @testset "Empty BalanceData Preserves Default Edge Contribution" begin
        timedata = make_test_timedata()

        start_node = Node{Electricity}(;
            id = :empty_start_node,
            timedata = timedata,
        )
        end_node = Node{Electricity}(;
            id = :empty_end_node,
            timedata = timedata,
            balance_data = Dict(:demand => BalanceData()),
        )
        edge = UnidirectionalEdge{Electricity}(;
            id = :empty_balance_edge,
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

        @add_balance(storage, :eq_balance, storage_level(storage) == 0.5 * capacity(storage))
        @add_balance(storage, :le_balance, storage_level(storage) <= 0.75 * capacity(storage))
        @add_balance(storage, :ge_balance, storage_level(storage) >= 0.25 * capacity(storage))

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

    @testset "Time-Varying Flow Coefficients Apply By Timestep" begin
        parts = make_test_transformation_with_edges(3)
        transform = parts.transform
        elec_edge = parts.elec_edge
        h2_edge = parts.h2_edge

        efficiency_profile = [0.6, 0.7, 0.8]

        @add_balance(
            transform,
            :energy,
            flow(elec_edge) + efficiency_profile * flow(h2_edge) == 0.0
        )

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

        for t in 1:3
            @constraint(model, flow(h2_edge, t) == 1.0)
        end
        @objective(model, Max, sum(flow(elec_edge, t) for t in 1:3))
        optimize!(model)

        @test is_solved_and_feasible(model)
        for (t, eff) in enumerate(efficiency_profile)
            @test value(flow(h2_edge, t)) ≈ 1.0 atol = 1e-8
            @test value(flow(elec_edge, t)) ≈ eff atol = 1e-8
            @test value(get_balance(transform, :energy, t)) ≈ 0.0 atol = 1e-8
        end
    end

    @testset "Incoming Edge Coefficients Preserve Electrolyzer-Style Efficiency" begin
        parts = make_test_transformation_with_edges(3)
        transform = parts.transform
        elec_edge = parts.elec_edge
        h2_edge = parts.h2_edge

        efficiency_profile = [0.6, 0.7, 0.8]

        @add_balance(
            transform,
            :energy,
            efficiency_profile * flow(elec_edge) + flow(h2_edge) == 0.0
        )

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

        for t in 1:3
            @constraint(model, flow(elec_edge, t) == 1.0)
        end
        @objective(model, Max, sum(flow(h2_edge, t) for t in 1:3))
        optimize!(model)

        @test is_solved_and_feasible(model)
        for (t, eff) in enumerate(efficiency_profile)
            @test value(flow(elec_edge, t)) ≈ 1.0 atol = 1e-8
            @test value(flow(h2_edge, t)) ≈ eff atol = 1e-8
            @test value(get_balance(transform, :energy, t)) ≈ 0.0 atol = 1e-8
        end
    end
end

end
