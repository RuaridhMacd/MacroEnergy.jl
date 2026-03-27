# Time Data

## Contents

[Overview](@ref "manual-timedata-overview") | [Input File](@ref "manual-timedata-input") | [Period Map](@ref "manual-timedata-periodmap") | [Subperiod Weights](@ref "manual-timedata-weights") | [TimeData Struct](@ref "manual-timedata-struct") | [Key Functions](@ref "manual-timedata-functions") | [Examples](@ref "manual-timedata-examples")

## [Overview](@id manual-timedata-overview)

Time data controls how Macro discretizes, represents, and weights time in an optimization model. Every node, edge, transformation, and storage component in a Macro system carries a `TimeData` object that defines its temporal resolution.

### Key Concepts

- **Time interval**: The full set of time steps in the simulation, determined by `NumberOfSubperiods × HoursPerSubperiod`.
- **Time step**: The smallest unit of time in the model for a given commodity. Currently fixed at 1 hour (`HoursPerTimeStep = 1`).
- **Subperiod**: A contiguous block of time steps (e.g., one representative week). Subperiods are used for time-wrapping in storage and other time-coupling constraints, as well as in the Benders decomposition algorithm.
- **Representative subperiods**: When the modeled time horizon is shorter than the full year, Macro uses a **period map** to assign each subperiod to a representative subperiod. This reduces the computational burden of the model optimization and enables efficient modeling of a full year using only a few representative weeks or days.
- **Subperiod weights**: Scaling factors that adjust operational costs and quantities so that a few representative subperiods correctly approximate the full modeled horizon.

## [Input File: `time_data.json`](@id manual-timedata-input)

**Format**: JSON

The `time_data.json` file is located in the `system/` folder and defines the temporal structure for all commodities. It is referenced in the [`system_data.json`](@ref "manual-system-data-structure") file.

### Structure

```json
{
    "NumberOfSubperiods": <Integer>,
    "HoursPerTimeStep": {
        "Commodity_1": <Integer>,
        "Commodity_2": <Integer>
    },
    "HoursPerSubperiod": {
        "Commodity_1": <Integer>,
        "Commodity_2": <Integer>
    },
    "SubPeriodMap": {
        "path": "<relative path to Period_map.csv>"
    },
    "TotalHoursModeled": <Integer>
}
```

### Attributes

| **Attribute** | **Type** | **Required** | **Default** | **Description** |
|:---|:---:|:---:|:---:|:---|
| `NumberOfSubperiods` | Integer | Yes | — | Number of representative subperiods in the simulation (e.g., 3 representative weeks). |
| `HoursPerTimeStep` | Dict | Yes | 1 | Number of hours per time step **for each commodity**. Must be `1` for now (sub-hourly and multi-hour time steps are not yet supported). |
| `HoursPerSubperiod` | Dict | Yes | — | Number of hours in each subperiod **for each commodity** (e.g., 168 for a week, 24 for a day). |
| `SubPeriodMap` | Dict | No | Identity map | Path to the period map CSV file or inline data. If omitted, each subperiod maps to itself and weights default to 1. |
| `TotalHoursModeled` | Integer | No | 8760 | Total hours the model represents (typically 8760 for one year). Used to compute subperiod weights when representative periods are used. |

!!! note "Commodity inheritance"
    Time data entries are matched to commodities by name. If a commodity (e.g., a user-defined sub-commodity) does not have an explicit entry in `HoursPerTimeStep` or `HoursPerSubperiod`, Macro will search the commodity's supertype hierarchy for a matching entry (e.g., `Electricity` for a sub-commodity of `Electricity`).

### How the time interval is computed

The total number of time steps for each commodity is:

```math
\text{TimeInterval} = 1 : (\texttt{NumberOfSubperiods} \times \texttt{HoursPerSubperiod})
```

The time interval is then partitioned into `NumberOfSubperiods` contiguous subperiods, each of length `HoursPerSubperiod`.

## [Period Map](@id manual-timedata-periodmap)

The **period map** links the full-year time horizon to the representative subperiods used in the optimization. It is provided as a CSV file (typically `Period_map.csv`) and referenced via the `SubPeriodMap` field in `time_data.json`:

```json
"SubPeriodMap": {
    "path": "system/Period_map.csv"
}
```

The **period map** allows Macro to:
1. **Compute subperiod weights**: scale operational costs and flows so that a few representative subperiods correctly approximate the full modeled time horizon (see [Subperiod Weights](@ref "manual-timedata-weights")).
2. **Model long-duration storage**: track storage state-of-charge across subperiod boundaries by identifying which subperiods are represented by the same representative subperiod.
3. **Run Benders decomposition**: group all modeled subperiods that share a representative into the same operational subproblem, reducing the number of subproblems solved.

### Format

The CSV file must have exactly three columns:

| **Column** | **Type** | **Description** |
|:---|:---:|:---|
| `Period_Index` | Integer | Index of the subperiod in the full time horizon (e.g., week 1 to 52 in a year). |
| `Rep_Period` | Integer | Index of the representative subperiod in the original time series that this subperiod is assigned to. |
| `Rep_Period_Index` | Integer | 1-based index of the representative subperiod as it appears in the modeled time horizon (matches the subperiod ordering in `time_data.json`). |

### Example: 52-week year with 3 representative weeks

Suppose you want to model a full year (52 weeks) using only 3 representative weeks, week 6, week 17, and week 32. You would set `NumberOfSubperiods` to 3 and provide a period map that assigns each of the 52 weeks to one of the 3 representative weeks: 

`Period_map.csv`:

| Period\_Index | Rep\_Period | Rep\_Period\_Index |
|:---:|:---:|:---:|
| 1 | 6 | 1 |
| 2 | 6 | 1 |
| 3 | 6 | 1 |
| ... | ... | ... |
| 10 | 17 | 2 |
| 11 | 6 | 1 |
| ... | ... | ... |
| 24 | 32 | 3 |
| ... | ... | ... |
| 52 | 6 | 1 |

In this example:
- Each of the 52 subperiods (weeks) is assigned to one of the 3 representative subperiods (week 6, week 17, or week 32);
- The `Period_Index` runs from 1 to 52, representing each week of the year;
- The `Rep_Period` column indicates which representative week each real week maps to (week 6, week 17, or week 32);
- The `Rep_Period_Index` column indicates the position of the representative subperiod in the modeled time horizon (1 for subperiod 6, 2 for subperiod 17, and 3 for subperiod 32). 
- In the table above, subperiods 1, 2, 3, 11, and 52 all map to representative week 6 (subperiod index 1), while subperiods 10 and 24 map to representative weeks 17 and 32 (subperiod indices 2 and 3), respectively.

!!! tip "Without a period map"
    If no `SubPeriodMap` is provided in `time_data.json`, Macro assumes each subperiod maps to itself (identity mapping). Weights are computed using the same formula as above, with $n_i = 1$ for each subperiod, giving $w_i = \texttt{TotalHoursModeled} / (\texttt{NumberOfSubperiods} \times \texttt{HoursPerSubperiod})$. This equals 1 only when `TotalHoursModeled` matches the total modeled hours exactly.

## [Subperiod Weights](@id manual-timedata-weights)

When representative periods are used, Macro computes a **weight** for each subperiod so that operational costs and energy quantities are correctly scaled to represent the full modeled horizon.

### Weight formula

The weight for the $i$-th representative period is:

```math
w_i = \alpha \cdot n_i
```

where $n_i$ is the number of times the $i$-th representative period appears in the period map, and $\alpha$ is a scaling factor:

```math
\alpha = \frac{\texttt{TotalHoursModeled}}{\sum_{i=1}^{N} \texttt{HoursPerSubperiod} \cdot n_i}
```

where $N$ is the total number of **unique** representative periods.

### Interpretation

- ``n_i`` counts how many subperiods are assigned to the $i$-th representative subperiod. A representative week assigned to 18 of the 52 subperiods has $n_i = 18$.
- ``\alpha`` rescales the weights so that the total weighted hours equal `TotalHoursModeled`. This accounts for any mismatch between the sum of mapped periods and the target time horizon.
- The weight $w_i$ is applied to each hour within the $i$-th subperiod when summing operational costs and flows.

### Example calculation

Using the period map from the example above (52 weeks, 3 representative weeks with `HoursPerSubperiod = 168` and `TotalHoursModeled = 8760`):

- Representative period 1 (week 6) appears in 18 of the 52 weeks → $n_1 = 18$
- Representative period 2 (week 17) appears in 21 of the 52 weeks → $n_2 = 21$
- Representative period 3 (week 32) appears in 13 of the 52 weeks → $n_3 = 13$

The scaling factor:

```math
\alpha = \frac{8760}{168 \times (18 + 21 + 13)} = \frac{8760}{168 \times 52} = \frac{8760}{8736} \approx 1.00275
```

The resulting weights:

| Rep\_Period\_Index | Rep\_Period | $n_i$ | $w_i = \alpha \cdot n_i$ |
|:---:|:---:|:---:|:---:|
| 1 | 6 | 18 | ≈ 18.05 |
| 2 | 17 | 21 | ≈ 21.06 |
| 3 | 32 | 13 | ≈ 13.04 |

These weights mean, for example, that each hour in representative period 1 counts as approximately 18.05 hours in the objective function, reflecting that this period represents 18 out of 52 real-world periods.

## [TimeData Struct](@id manual-timedata-struct)

Internally, Macro stores the processed time configuration in a `TimeData{T}` struct, parameterized by the commodity type `T`.

### Fields

| **Field** | **Type** | **Description** |
|:---|:---|:---|
| `time_interval` | `StepRange{Int64,Int64}` | Full range of time steps (e.g., `1:504`). |
| `hours_per_timestep` | `Int64` | Hours represented by each time step. |
| `period_index` | `Int64` | Index of the current planning period (used in multi-period models). Default: `1`. |
| `subperiods` | `Vector{StepRange{Int64,Int64}}` | List of time step ranges for each subperiod (e.g., `[1:168, 169:336, 337:504]`). |
| `subperiod_indices` | `Vector{Int64}` | Unique subperiod indices of the representative periods (e.g., `[6, 17, 32]`). |
| `subperiod_weights` | `Dict{Int64,Float64}` | Weight for each representative subperiod, keyed by its `Rep_Period` value (e.g., `{6 => 18.05, 17 => 21.06, 32 => 13.04}`). |
| `subperiod_map` | `Dict{Int64,Int64}` | Maps each subperiod index to its representative subperiod index (e.g., `{1 => 6, 2 => 6, 3 => 6, ..., 10 => 17, 11 => 6, 24 => 32, 52 => 6}`). |

### Type hierarchy

`TimeData{T}` is a subtype of `AbstractTimeData{T}`, where `T` is any `Commodity` type (e.g., `Electricity`, `Hydrogen`).

## [Key Functions](@id manual-timedata-functions)

The following functions provide access to time data from vertices and edges (`y`) in the system:

| **Function** | **Description** |
|:---|:---|
| `time_interval(y)` | Returns the full time interval for component `y`. |
| `hours_per_timestep(y)` | Returns the number of hours per time step. |
| `subperiods(y)` | Returns the list of subperiod ranges. |
| `subperiod_indices(y)` | Returns the unique representative period indices. |
| `subperiod_weight(y, w)` | Returns the weight for representative period `w`. |
| `subperiod_map(y)` | Returns the full period map dictionary. |
| `current_subperiod(y, t)` | Returns the subperiod index containing time step `t`. |
| `get_subperiod(y, w)` | Returns the time step range for representative period `w`. |

### [`timestepbefore`](@ref)

The [`timestepbefore`](@ref) function computes the time step that is `h` steps before index `t` with **circular indexing** within a subperiod. This is critical for time-coupling constraints such as storage state-of-charge tracking, where the last time step of a subperiod wraps around to the first.

## [Examples](@id manual-timedata-examples)

### Simple case: 3 days, no representative periods

Model 3 full days with hourly resolution for electricity and natural gas:

```json
{
    "NumberOfSubperiods": 3,
    "HoursPerTimeStep": {
        "Electricity": 1,
        "NaturalGas": 1,
        "CO2": 1
    },
    "HoursPerSubperiod": {
        "Electricity": 24,
        "NaturalGas": 24,
        "CO2": 24
    },
    "TotalHoursModeled": 8760
}
```

Without a `SubPeriodMap`, this produces:
- **Time interval**: `1:72` (3 × 24 = 72 time steps)
- **Subperiods**: `[1:24, 25:48, 49:72]`
- **Weights**: `8760 / (3 × 24) ≈ 121.67` for each subperiod — each modeled day is scaled to represent approximately 121.67 hours of the full year

### Full case: 3 representative weeks with period map

Model a full year using 3 representative weeks, hourly resolution:

```json
{
    "NumberOfSubperiods": 3,
    "HoursPerTimeStep": {
        "Electricity": 1,
        "Hydrogen": 1,
        "NaturalGas": 1,
        "CO2": 1,
        "Uranium": 1
    },
    "HoursPerSubperiod": {
        "Electricity": 168,
        "Hydrogen": 168,
        "NaturalGas": 168,
        "CO2": 168,
        "Uranium": 168
    },
    "SubPeriodMap": {
        "path": "system/Period_map.csv"
    },
    "TotalHoursModeled": 8760
}
```

This produces:
- **Time interval**: `1:504` (3 × 168 = 504 time steps)
- **Subperiods**: `[1:168, 169:336, 337:504]`
- **Weights**: Computed from the period map (see [Subperiod Weights](@ref "manual-timedata-weights"))