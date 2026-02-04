function total_years(period_lengths::Vector{Int})
    return sum(period_lengths; init=0)
end

function period_start_years(period_lengths::Vector{Int})
    if isempty(period_lengths)
        return [0]
    end
    n = length(period_lengths)
    result = Vector{Int}(undef, n)
    result[1] = 0
    @inbounds for i in 2:n
        result[i] = result[i-1] + period_lengths[i-1]
    end
    return result
end

function present_value_factor(discount_rate::Float64, total_years::Int)
    # Using a different name than discount factor to avoid overwriting
    return 1 / ( (1 + discount_rate) ^ total_years)
end

function present_value_factor(discount_rate::Float64, period_lengths::Vector{Int})
    return present_value_factor.(discount_rate, period_start_years(period_lengths))
end

function capital_recovery_factor(discount_rate::Float64, total_years::Int)
    return discount_rate / (1 - (1 + discount_rate) ^ (-total_years))
end

function opex_multiplier(discount_rate::Float64, total_years::Int)
    # sum(1 / (1 + discount_rate)^i) for i 1:N = (1 - (1 + discount_rate)^-N) / discount_rate = 1 / CRF
    return 1 / capital_recovery_factor(discount_rate, total_years)
end