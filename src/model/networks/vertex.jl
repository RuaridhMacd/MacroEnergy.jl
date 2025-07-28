const BalanceData = @NamedTuple{id::Symbol, var::Symbol, coeff::Float64}
macro empty_balance_data()
    BalanceData(id = :empty, var = :empty, coeff = 0.0)
end
"""
    @AbstractVertexBaseAttributes()

    A macro that defines the base attributes for all vertex types in the network model.

    # Generated Fields
    - id::Symbol: Unique identifier for the vertex
    - timedata::TimeData: Time-related data for the vertex
    - balance_data::Dict{Symbol,Dict{Symbol,Float64}}: Dictionary mapping balance equation IDs to coefficients
    - constraints::Vector{AbstractTypeConstraint}: List of constraints applied to the vertex
    - operation_expr::Dict: Dictionary storing operational JuMP expressions for the vertex

    This macro is used to ensure consistent base attributes across all vertex types in the network.
"""
macro AbstractVertexBaseAttributes()
    esc(
        quote
            id::Symbol
            timedata::TimeData
            location::Union{Missing, Symbol} = missing
            balance_data::Dict{Symbol, Vector{BalanceData}} = Dict{Symbol, Vector{BalanceData}}()
            constraints::Vector{AbstractTypeConstraint} = Vector{AbstractTypeConstraint}()
            operation_expr::Dict = Dict()
        end,
    )
end

"""
    id(v::AbstractVertex)

Get the unique identifier (ID) of a vertex.

# Arguments
- `v`: A vertex object that is a subtype of AbstractVertex (i.e., `Node`, `Storage`, `Transformation`)

# Returns
- A Symbol representing the vertex's unique identifier

# Examples
```julia
vertex_id = id(elec_node)
```
"""
id(v::AbstractVertex) = v.id

"""
    balance_ids(v::AbstractVertex)

Get the IDs of all balance equations in a vertex.

# Arguments
- `v`: A vertex object that is a subtype of AbstractVertex

# Returns
- A vector of Symbols representing the IDs of all balance equations

# Examples
```julia
balance_ids = balance_ids(elec_node)
```
"""
balance_ids(v::AbstractVertex) = collect(keys(v.balance_data))

balance_ids(data::BalanceData) = data.id

balance_ids(data::Vector{BalanceData}) = [d.id for d in data]

# Function find_balance(data::Vector{BalanceData}, id::Symbol, var::Symbol) which 
# return the index of the first BalanceData with matching id and var
function find_balance(data::Vector{BalanceData}, id::Symbol, var::Symbol)
    return findfirst(d -> d.id == id && d.var == var, data)
end

"""
    balance_data(v::AbstractVertex, i::Symbol)

Get the input data for a specific balance equation in a vertex.

# Arguments
- `v`: A vertex object that is a subtype of AbstractVertex
- `i`: Symbol representing the ID of the balance equation

# Returns
- The input data (usually stoichiometric coefficients) for the specified balance equation

# Examples
```julia
demand_data = balance_data(elec_node, :demand)
```
"""
balance_data(v::AbstractVertex, i::Symbol) = v.balance_data[i]

"""
    get_balance(v::AbstractVertex, i::Symbol)

Get the mathematical expression of a balance equation in a vertex.

# Arguments
- `v`: A vertex object that is a subtype of AbstractVertex
- `i`: Symbol representing the ID of the balance equation

# Returns
- The mathematical expression of the balance equation

# Examples
```julia
# Get the demand balance expression
demand_expr = get_balance(elec_node, :demand)
```
"""
get_balance(v::AbstractVertex, i::Symbol) = v.operation_expr[i]
get_balance(v::AbstractVertex, i::Symbol, t::Int64) = get_balance(v, i)[t]

"""
    all_constraints(v::AbstractVertex)

Get all constraints on a vertex.

# Arguments
- `v`: A vertex object that is a subtype of AbstractVertex

# Returns
- A vector of all constraint objects on the vertex

# Examples
```julia
constraints = all_constraints(elec_node)
```
"""
all_constraints(v::AbstractVertex) = v.constraints

"""
    all_constraints_types(v::AbstractVertex)

Get the types of all constraints on a vertex.

# Arguments
- `v`: A vertex object that is a subtype of AbstractVertex

# Returns
- A vector of types of all constraints on the vertex

# Examples
```julia
constraint_types = all_constraints_types(elec_node)
```
"""
all_constraints_types(v::AbstractVertex) = [typeof(c) for c in all_constraints(v)]

"""
    get_constraint_by_type(v::AbstractVertex, constraint_type::Type{<:AbstractTypeConstraint})

Get a constraint on a vertex by its type.

# Arguments
- `v`: A vertex object that is a subtype of AbstractVertex
- `constraint_type`: The type of constraint to find

# Returns
- If exactly one constraint of the specified type exists: returns that constraint
- If multiple constraints of the specified type exist: returns a vector of those constraints
- If no constraints of the specified type exist: returns `nothing`

# Examples
```julia
balance_constraint = get_constraint_by_type(elec_node, BalanceConstraint)
```
"""
function get_constraint_by_type(v::AbstractVertex, constraint_type::Type{<:AbstractTypeConstraint})
    constraints = all_constraints(v)
    matches = filter(c -> typeof(c) == constraint_type, constraints)
    return length(matches) == 1 ? matches[1] : length(matches) > 1 ? matches : nothing
end

function reformat_balance_data(data::Dict{Symbol,Float64}, var::Symbol = :flow)
    return BalanceData[
        (id = k, var = var, coeff = v) for (k, v) in data
    ]
end

function add_balance_data(v::AbstractVertex, balance_id::Symbol, data::Dict{Symbol, Float64})
    if haskey(v.balance_data, balance_id)
        append!(v.balance_data[balance_id], reformat_balance_data(data))
    else
        v.balance_data[balance_id] = reformat_balance_data(data)
    end
    return nothing
end

function add_balance_data(v::AbstractVertex, balance_id::Symbol, data::Vector{BalanceData})
    if haskey(v.trial_data, balance_id)
        append!(v.trial_data[balance_id], data)
    else
        v.trial_data[balance_id] = data
    end
    return nothing
end

function parse_balance_eq(ex)
    if ex isa Number
        return [(id = :constant, var = :constant, coeff = Float64(ex))]
    
    elseif ex isa Symbol
        return [(id = :constant, var = :constant, coeff = 0.0)]  # Just in case

    elseif ex isa Expr
        if ex.head == :call
            f = ex.args[1]
            # Addition and subtraction
            if f == :+ || f == :-
                lhs = parse_balance_eq(ex.args[2])
                rhs = parse_balance_eq(ex.args[3])
                if f == :-
                    rhs = [(id = t.id, var = t.var, coeff = -t.coeff) for t in rhs]
                end
                return vcat(lhs, rhs)

            # Multiplication
            elseif f == :*
                if ex.args[2] isa Number
                    coeff = Float64(ex.args[2])
                    terms = parse_balance_eq(ex.args[3])
                elseif ex.args[3] isa Number
                    coeff = Float64(ex.args[3])
                    terms = parse_balance_eq(ex.args[2])
                else
                    error("Unsupported multiplication format in: $ex")
                end
                return [(id = t.id, var = t.var, coeff = coeff * t.coeff) for t in terms]

            # Negation
            elseif f == :- && length(ex.args) == 2
                terms = parse_expr(ex.args[2])
                return [(id = t.id, var = t.var, coeff = -t.coeff) for t in terms]

            # Function calls like flow(:x)
            else
                if length(ex.args) == 2 && ex.args[2] isa QuoteNode
                    return [(id = ex.args[2].value, var = f, coeff = 1.0)]
                else
                    error("Unrecognized function term: $ex")
                end
            end
        end
    end
    error("Unrecognized expression: $ex")
end

function combine_constants!(terms::Vector{BalanceData})
    # If terms contains any id = :constant terms
    # then Add together all id = :constant terms
    constant_terms = filter(t -> t.id == :constant, terms)
    if !isempty(constant_terms)
        constant_value = sum(t.coeff for t in constant_terms)
        terms = filter(t -> t.id != :constant, terms)
        if constant_value != 0.0
            push!(terms, (id = :constant, var = :constant, coeff = constant_value))
        end
    end
    return terms
end

"""
    @add_balance(component, balance_id, equation)

A macro to add balance equation data to a component in a structured format.

# Arguments
- `component`: The component object to add balance data to
- `balance_id`: Symbol key for the balance equation (e.g., `:energy`, `:mass`)
- `equation`: Balance equation with operators: ==, =, <=, <, >=, >

# Examples
```julia
@add_balance(node, :energy, flow(:power) == 0.5 * flow(:hydrogen))
@add_balance(node, :mass, flow(:input) <= 2.0 * flow(:output))
```
"""
macro add_balance(component, balance_id, equation)
    # Step 1: Parse the equation and identify the operator
    if !isa(equation, Expr) || equation.head != :call
        error("Expected an equation expression, got: $equation")
    end
    
    operator = equation.args[1]
    left_side = equation.args[2]
    right_side = equation.args[3]
    
    # Check if operator is supported
    supported_ops = [:(==), :(=), :(<=), :(<), :(>=), :(>)]
    if operator ∉ supported_ops
        error("Your balance constraint has an unsupported operator: $expr. Supported operators: $supported_ops")
    end
    
    # Step 2: Handle >= and > by flipping sides and converting to <= and <
    if operator == :(>=)
        operator = :(<=)
        left_side, right_side = right_side, left_side
        @debug("Converted >= to <= by flipping sides")
    elseif operator == :(>)
        operator = :(<)
        left_side, right_side = right_side, left_side
        @debug("Converted > to < by flipping sides")
    end
    
    # Step 3: Move everything to left side (LHS - RHS)
    # For now, let's just normalize to LHS - RHS and return the normalized expression
    normalized_expr = :($left_side - $right_side)
    
    @debug("Original equation: $equation")
    @debug("Final operator: $operator")
    @debug("Left side: $left_side")
    @debug("Right side: $right_side")
    @debug("Normalized (LHS - RHS): $normalized_expr")

    terms = parse_balance_eq(normalized_expr)
    combine_constants!(terms)
    @debug(terms)

    # Embed the computed terms directly into the generated code
    return esc(:(
        add_balance_data(
            $component,
            $balance_id,
            $terms
        )
    ))
end