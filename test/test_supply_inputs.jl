module TestSupplyInputs

using Test
using MacroEnergy
using OrderedCollections: OrderedDict

import MacroEnergy: check_and_convert_supply!

function test_empty_price_supply_normalizes_to_empty_segments()
    data = Dict{Symbol,Any}(:price_supply => Float64[])

    check_and_convert_supply!(data)

    @test data[:price_supply] == OrderedDict{Symbol,Vector{Float64}}()
    @test data[:max_supply] == OrderedDict{Symbol,Vector{Float64}}()
    @test data[:supply_segment_names] == Symbol[]
end

function test_single_vector_price_supply_defaults_to_inf_max_supply()
    data = Dict{Symbol,Any}(:price_supply => [5.0, 6.0])

    check_and_convert_supply!(data)

    @test data[:price_supply] == OrderedDict(:seg1 => [5.0, 6.0])
    @test data[:min_supply] == OrderedDict(:seg1 => [0.0])
    @test data[:max_supply] == OrderedDict(:seg1 => [Inf])
    @test data[:supply_segment_names] == [:seg1]
end

function test_single_segment_dict_preserves_segment_name_without_max_supply()
    data = Dict{Symbol,Any}(:price_supply => OrderedDict(:gas => [5.0, 6.0]))

    check_and_convert_supply!(data)

    @test data[:price_supply] == OrderedDict(:gas => [5.0, 6.0])
    @test data[:max_supply] == OrderedDict(:gas => [Inf])
    @test data[:supply_segment_names] == [:gas]
end

function test_vector_vector_inputs_are_segmented_and_named()
    data = Dict{Symbol,Any}(
        :price_supply => [5.0, 9.0],
        :max_supply => [10.0, 20.0],
        :supply_segment_names => [:cheap, :firm],
    )

    check_and_convert_supply!(data)

    @test data[:price_supply] == OrderedDict(:cheap => [5.0], :firm => [9.0])
    @test data[:max_supply] == OrderedDict(:cheap => [10.0], :firm => [20.0])
    @test data[:supply_segment_names] == [:cheap, :firm]
end

function test_vector_vector_inputs_pad_and_trim_names()
    short_names = Dict{Symbol,Any}(
        :price_supply => [5.0, 9.0],
        :max_supply => [10.0, 20.0],
        :supply_segment_names => [:a],
    )
    long_names = Dict{Symbol,Any}(
        :price_supply => [5.0, 9.0],
        :max_supply => [10.0, 20.0],
        :supply_segment_names => [:a, :b, :c],
    )

    check_and_convert_supply!(short_names)
    check_and_convert_supply!(long_names)

    @test short_names[:supply_segment_names] == [:a, :seg1]
    @test short_names[:price_supply] == OrderedDict(:a => [5.0], :seg1 => [9.0])
    @test long_names[:supply_segment_names] == [:a, :b]
    @test long_names[:price_supply] == OrderedDict(:a => [5.0], :b => [9.0])
end

function test_mixed_vector_and_dict_inputs_normalize_max_supply()
    vector_price = Dict{Symbol,Any}(
        :price_supply => [5.0, 9.0],
        :max_supply => OrderedDict(:cheap => 10.0, :firm => 20.0),
    )
    vector_max = Dict{Symbol,Any}(
        :price_supply => OrderedDict(:cheap => [5.0], :firm => [9.0]),
        :max_supply => [10.0, 20.0],
    )

    check_and_convert_supply!(vector_price)
    check_and_convert_supply!(vector_max)

    @test vector_price[:price_supply] == OrderedDict(:cheap => [5.0], :firm => [9.0])
    @test vector_price[:max_supply] == OrderedDict(:cheap => [10.0], :firm => [20.0])
    @test vector_price[:supply_segment_names] == [:cheap, :firm]

    @test vector_max[:price_supply] == OrderedDict(:cheap => [5.0], :firm => [9.0])
    @test vector_max[:max_supply] == OrderedDict(:cheap => [10.0], :firm => [20.0])
    @test vector_max[:supply_segment_names] == [:cheap, :firm]
end

function test_dict_inputs_convert_numeric_scalars_to_float_vectors()
    data = Dict{Symbol,Any}(
        :price_supply => OrderedDict(:seg1 => 5),
        :min_supply => OrderedDict(:seg1 => 3),
        :max_supply => OrderedDict(:seg1 => 10),
    )

    check_and_convert_supply!(data)

    @test data[:price_supply] == OrderedDict(:seg1 => [5.0])
    @test data[:min_supply] == OrderedDict(:seg1 => [3.0])
    @test data[:max_supply] == OrderedDict(:seg1 => [10.0])
    @test data[:supply_segment_names] == [:seg1]
end

function test_min_supply_defaults_to_zero_when_not_provided()
    data = Dict{Symbol,Any}(
        :price_supply => OrderedDict(:cheap => [5.0], :firm => [9.0]),
        :max_supply => OrderedDict(:cheap => [10.0], :firm => [20.0]),
    )

    check_and_convert_supply!(data)

    @test data[:min_supply] == OrderedDict(:cheap => [0.0], :firm => [0.0])
end

function test_min_supply_vector_input_errors()
    data = Dict{Symbol,Any}(
        :price_supply => OrderedDict(:seg1 => [5.0]),
        :max_supply => OrderedDict(:seg1 => [10.0]),
        :min_supply => [1.0],
    )

    @test_throws ArgumentError check_and_convert_supply!(data)
end

function test_min_supply_greater_than_max_supply_errors()
    data = Dict{Symbol,Any}(
        :price_supply => OrderedDict(:seg1 => [5.0, 6.0]),
        :max_supply => OrderedDict(:seg1 => [10.0, 10.0]),
        :min_supply => OrderedDict(:seg1 => [8.0, 12.0]),
    )

    @test_throws ArgumentError check_and_convert_supply!(data)
end

function test_multi_segment_price_supply_without_max_supply_errors()
    data = Dict{Symbol,Any}(
        :price_supply => OrderedDict(:seg1 => [5.0], :seg2 => [9.0]),
    )

    @test_throws ArgumentError check_and_convert_supply!(data)
end

function test_extra_names_without_max_supply_errors()
    data = Dict{Symbol,Any}(
        :price_supply => [5.0, 6.0],
        :supply_segment_names => [:a, :b],
    )

    @test_throws ArgumentError check_and_convert_supply!(data)
end

@testset "Supply Inputs" begin
    test_empty_price_supply_normalizes_to_empty_segments()
    test_single_vector_price_supply_defaults_to_inf_max_supply()
    test_single_segment_dict_preserves_segment_name_without_max_supply()
    test_vector_vector_inputs_are_segmented_and_named()
    test_vector_vector_inputs_pad_and_trim_names()
    test_mixed_vector_and_dict_inputs_normalize_max_supply()
    test_dict_inputs_convert_numeric_scalars_to_float_vectors()
    test_min_supply_defaults_to_zero_when_not_provided()
    test_min_supply_vector_input_errors()
    test_min_supply_greater_than_max_supply_errors()
    test_multi_segment_price_supply_without_max_supply_errors()
    test_extra_names_without_max_supply_errors()
end

end # module TestSupplyInputs