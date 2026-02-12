module TestUserAdditions
"""
Tests for user-defined commodity additions and persistence behavior.

These tests verify that custom subcommodity definitions:
- resolve correctly when listed out of order,
- fail fast on circular parent dependencies,
- are written to file deterministically without duplicates.
"""

using Test

import MacroEnergy:
    load_commodities,
    commodity_types,
    register_commodity_types!,
    write_user_subcommodities,
    user_additions_subcommodities_path

"""
Generate a unique symbol for dynamically-defined test commodity types.

Using unique names avoids collisions with prior test runs in the same Julia session.
"""
function unique_test_symbol(prefix::AbstractString)
    return Symbol("$(prefix)_$(time_ns())")
end

"""
Verify that chained user-defined subcommodities resolve correctly even when inputs are out of order.

Expected behavior:
- parent type is created first through iterative resolution,
- child types are then created and registered,
- resulting type hierarchy matches parent-child declarations.
"""
function test_chained_subcommodities_out_of_order()
    register_commodity_types!()

    diesel = unique_test_symbol("TestDiesel")
    clean_diesel = unique_test_symbol("TestCleanDiesel")
    dirty_diesel = unique_test_symbol("TestDirtyDiesel")

    commodities = Any[
        Dict{Symbol,Any}(:name => String(clean_diesel), :acts_like => String(diesel)),
        Dict{Symbol,Any}(:name => String(dirty_diesel), :acts_like => String(diesel)),
        Dict{Symbol,Any}(:name => String(diesel), :acts_like => "LiquidFuels"),
    ]

    loaded = load_commodities(commodities, ""; write_subcommodities=false)
    macro_commodities = commodity_types()
    liquid_fuels = macro_commodities[:LiquidFuels]

    @test haskey(loaded, diesel)
    @test haskey(loaded, clean_diesel)
    @test haskey(loaded, dirty_diesel)

    @test macro_commodities[diesel] <: liquid_fuels
    @test macro_commodities[clean_diesel] <: macro_commodities[diesel]
    @test macro_commodities[dirty_diesel] <: macro_commodities[diesel]
end

"""
Verify that circular subcommodity dependencies are rejected with a clear error.

Expected behavior:
- no subtype definitions are applied for unresolved cycles,
- loader throws an informative error about unknown/circular parents.
"""
function test_circular_subcommodities_error()
    register_commodity_types!()

    commodity_a = unique_test_symbol("TestCommodityA")
    commodity_b = unique_test_symbol("TestCommodityB")

    commodities = Any[
        Dict{Symbol,Any}(:name => String(commodity_a), :acts_like => String(commodity_b)),
        Dict{Symbol,Any}(:name => String(commodity_b), :acts_like => String(commodity_a)),
    ]

    @test_throws "Unknown or circular parent commodities" load_commodities(commodities, ""; write_subcommodities=false)
end

"""
Verify deterministic and de-duplicated persistence of generated subcommodity lines.

Expected behavior:
- existing file order is preserved,
- duplicate and blank lines are ignored,
- only new unique definitions are appended.
"""
function test_subcommodities_file_write_order()
    case_path = mktempdir()

    write_user_subcommodities(case_path, [
        "abstract type TestA <: MacroEnergy.LiquidFuels end",
        "abstract type TestB <: MacroEnergy.LiquidFuels end",
        "abstract type TestA <: MacroEnergy.LiquidFuels end",
    ])

    write_user_subcommodities(case_path, [
        "",
        "abstract type TestB <: MacroEnergy.LiquidFuels end",
        "abstract type TestC <: MacroEnergy.LiquidFuels end",
    ])

    lines = readlines(user_additions_subcommodities_path(case_path))
    @test lines == [
        "abstract type TestA <: MacroEnergy.LiquidFuels end",
        "abstract type TestB <: MacroEnergy.LiquidFuels end",
        "abstract type TestC <: MacroEnergy.LiquidFuels end",
    ]
end

"""
Verify that persisted subcommodity definitions are dependency ordered.

Expected behavior:
- if a child line is seen before its parent line,
- writer rewrites file so parent definition appears first.
"""
function test_subcommodities_dependency_write_order()
    case_path = mktempdir()

    write_user_subcommodities(case_path, [
        "abstract type TestChildFuel <: MacroEnergy.TestParentFuel end",
        "abstract type TestParentFuel <: MacroEnergy.LiquidFuels end",
    ])

    lines = readlines(user_additions_subcommodities_path(case_path))
    @test lines == [
        "abstract type TestParentFuel <: MacroEnergy.LiquidFuels end",
        "abstract type TestChildFuel <: MacroEnergy.TestParentFuel end",
    ]
end

"""
Run all user additions tests.
"""
function test_user_additions()
    @testset "Chained subcommodities" begin
        test_chained_subcommodities_out_of_order()
    end

    @testset "Circular dependency handling" begin
        test_circular_subcommodities_error()
    end

    @testset "Deterministic subcommodity writes" begin
        test_subcommodities_file_write_order()
    end

    @testset "Dependency-ordered subcommodity writes" begin
        test_subcommodities_dependency_write_order()
    end

    return nothing
end

test_user_additions()

end # module TestUserAdditions
