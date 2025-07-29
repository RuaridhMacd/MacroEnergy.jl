const BalanceData = @NamedTuple{id::Symbol, var::Symbol, coeff::Float64}
macro empty_balance_data()
    (id = :empty, var = :empty, coeff = 0.0)
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
    if haskey(v.balance_data, balance_id)
        append!(v.balance_data[balance_id], data)
    else
        v.balance_data[balance_id] = data
    end
    return nothing
end

function parse_balance_eq(ex)
    if isa(ex, Number)
        return [(id = :constant, var = :constant, coeff = Float64(ex))]

    elseif isa(ex, Symbol)
        return [(id = :constant, var = :constant, coeff = 0.0)]  # Just in case

    elseif isa(ex, Expr)
        if ex.head == :call
            args = ex.args
            len = length(args)
            f = args[1]
            if len == 1
                error("Functions with no arguments are not supported: $ex")
            elseif len == 2
                if f == :-
                    terms = parse_balance_eq(args[2])[1]
                    return [(id = terms[2], var = terms[1], coeff = -terms[3])]
                else
                    # Extract symbol from QuoteNode if needed
                    # id_val = args[2] isa QuoteNode ? args[2].value : args[2]
                    return [(id = args[2], var = args[1], coeff = 1.0)]
                end
            else
                if f == :+
                    # Addition, where we must allow for associativity leading to 
                    # any number of terms
                    term_vectors = [parse_balance_eq(args[i]) for i in 2:len]
                    return vcat(term_vectors...) 
                elseif f == :-
                    # Subtraction, will always have 3 args
                    # We need to negate the right-hand side
                    lhs = parse_balance_eq(ex.args[2])
                    rhs = parse_balance_eq(ex.args[3])
                    rhs = [(id = t.id, var = t.var, coeff = -t.coeff) for t in rhs]
                    return vcat(lhs, rhs)
                elseif f == :*
                    # Multiplication, where we assume the last term is the variable
                    # as associativity means we can have any number of terms
                    if len == 3
                        term1 = ex.args[2]
                    else
                        term1 = Expr(:call, f, ex.args[2:end-1]...)
                    end 
                    println(term1)
                    term2 = ex.args[end]
                    if isa(term1, Number) || isa(term2, Number)
                        if isa(ex.args[2], Number)
                            coeff = Float64(ex.args[2])
                            terms = parse_balance_eq(ex.args[3])
                        elseif isa(ex.args[3], Number)
                            coeff = Float64(ex.args[3])
                            terms = parse_balance_eq(ex.args[2])
                        end
                        return [(id = t.id, var = t.var, coeff = coeff * t.coeff) for t in terms]
                    end
                    terms = parse_balance_eq(term2)
                    return [t.coeff == 1.0 ? (id = t.id, var = t.var, coeff = term1) : (id = t.id, var = t.var, coeff = Expr(:call, :*, term1, t.coeff)) for t in terms]
                end
            end
            error("Unrecognized expression format: $ex")
        end
    end
    error("Unrecognized expression: $ex")
end

function post_process_terms(terms::Vector{<:NamedTuple{(:id, :var, :coeff)}})
    constant_terms = filter(t -> t.id == :constant, terms)
    constant_term = combine_constants!(constant_terms)

    terms = filter(t -> t.id != :constant, terms)
    terms_expr = [
        :((id=$(Expr(:., t.id, QuoteNode(:id))), var=$(QuoteNode(t.var)), coeff=$(t.coeff))) for t in terms
    ]

    if !isnothing(constant_term)
        constant_term_expr = :((id=$(QuoteNode(constant_term.id)), var=$(QuoteNode(constant_term.var)), coeff=$(constant_term.coeff)))
        terms_expr = vcat(terms_expr, constant_term_expr)
    end

    return terms_expr
end

function add_id(terms::Vector{<:NamedTuple{(:id, :var, :coeff)}})
    # Add ".id" to all the ids which are not :constant
    for i in eachindex(terms)
        if terms[i].id != :constant
            terms[i] = (id = Expr(:call, :id, terms[i].id), var = terms[i].var, coeff = terms[i].coeff)
        end
    end
    return terms
end

function combine_constants!(constant_terms::Vector{<:NamedTuple{(:id, :var, :coeff)}})
    # If terms contains any id = :constant terms
    # then add together all id = :constant terms
    if !isempty(constant_terms)
        constant_value = sum(t.coeff for t in constant_terms)
        if constant_value != 0.0
            return (id = :constant, var = :constant, coeff = constant_value)
        end
    end
    return nothing
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
    println("Normalized (LHS - RHS): $normalized_expr")

    terms = parse_balance_eq(normalized_expr)
    println.(terms)
    println(typeof(terms))
    println(" ----- ")
    for t in terms
        println(typeof(t))
        println(typeof(t) == BalanceData)
        println(typeof(t.id))
        println(typeof(t.var))
        println(typeof(t.coeff))
    end
    terms = post_process_terms(terms)

    println(" ----- ")
    println.(terms)
    println(typeof(terms))
    println(" ----- ")

    # Embed the computed terms directly into the generated code
    return esc(quote
        add_balance_data(
            $component,
            $balance_id,
            BalanceData[ $(terms...) ]  # splices into array
        )
    end)
end