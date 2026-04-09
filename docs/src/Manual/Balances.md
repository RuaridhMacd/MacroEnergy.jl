# Balances

Balances in Macro define algebraic relationships between variables on a `Node`, `Transformation`, or `Storage`. They are used by [`BalanceConstraint`](@ref balance_constraint_ref) to build one constraint per balance ID and time step.

## Overview

At the user and modeler level, balances are usually defined with macros in asset `make` functions:

- `@add_balance` for general balances
- `@add_stoichiometric_balance` for chemical-style `-->` shorthand

Under the hood, each balance is stored as a `BalanceData` object containing:

- a `sense` (`:eq`, `:le`, or `:ge`)
- a list of `BalanceTerm`s
- an optional constant term

Each `BalanceTerm` points to an object and variable, plus a coefficient. This is what allows balances to include variables beyond `flow(...)`.

## Supported Balance Terms

The most common balance terms are:

- `flow(edge)`
- `capacity(edge_or_storage)`
- `existing_capacity(edge_or_storage)`
- `new_capacity(edge_or_storage)`
- `retired_capacity(edge_or_storage)`
- `storage_level(storage)`

Scalar coefficients are supported, as are time-varying coefficient profiles.

## Coefficients

Macro supports three coefficient forms in `@add_balance`:

1. A single number, used at every time step.
2. A vector of length `1`, which is treated like a scalar.
3. A vector with one entry per time step of the host vertex, used as a time-varying coefficient profile.

## Equality And Inequality Balances

Balances may be written as equalities or inequalities.

```julia
@add_balance(transform, :energy, flow(elec_edge) == eff * flow(h2_edge))
@add_balance(storage, :upper, storage_level(storage) <= capacity(storage))
@add_balance(
    transform,
    :energy_lb,
    flow(elec_edge) >= eff * flow(h2_edge) - area * capacity(h2_edge),
)
```

These become `==`, `<=`, and `>=` `BalanceConstraint`s respectively.

## Stoichiometric Shorthand

`@add_stoichiometric_balance` is a convenience macro for recipe-style or chemical-style relationships written with `-->`.

It expands a single stoichiometric expression into multiple pairwise balances, each anchored on the chosen `base_term`. In the example below, `flow(h2_edge)` is the base term, so Macro generates ordinary balances that each include `flow(h2_edge)`.

```julia
@add_stoichiometric_balance(
    electrolyzer,
    :energy,
    efficiency_rate * flow(elec_edge) + water_consumption * flow(water_edge) -->
    flow(h2_edge),
    flow(h2_edge),
)
```

Conceptually, this is useful when you want to express a conversion as a recipe and then have Macro break it into pairwise relationships. The example above expands into balances equivalent to:

```julia
@add_balance(
    electrolyzer,
    :energy_1,
    flow(h2_edge) + efficiency_rate * flow(elec_edge) == 0.0,
)
@add_balance(
    electrolyzer,
    :energy_2,
    flow(h2_edge) + water_consumption * flow(water_edge) == 0.0,
)
```

Notice that the generated balances are normalized around the chosen `base_term`. Here that means one balance relates hydrogen to electricity, and a second balance relates hydrogen to water.

Use this when the asset is easiest to describe as a stoichiometric conversion. For more general balances, `@add_balance` is the preferred interface.

## Legacy Balance Dictionaries

Legacy balance definitions of the form

```julia
Dict(:energy => Dict(edge_id => coeff))
```

are still normalized internally for backwards compatibility. New asset code should prefer `@add_balance`.

## Node, Transformation, And Storage Balances

### Node Balances

Nodes commonly use balances to:

- enforce demand balance
- track policy-related balance expressions
- aggregate or split flows of a commodity

### Transformation Balances

Transformations use balances to describe conversion relationships such as:

- efficiencies
- mass balances
- emissions rates
- auxiliary consumption terms

### Storage Balances

Storage balances are used for:

- state-of-charge accounting
- charge/discharge efficiencies
- capacity envelopes such as `storage_level(storage) <= capacity(storage)`
