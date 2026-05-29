# [Capacity Output](@id manual-outputs-capacity)

## Contents

[Overview](@ref "manual-outputs-capacity-overview") | [Columns](@ref "manual-outputs-capacity-columns") | [Variable Types](@ref "manual-outputs-capacity-variables") | [Configuration](@ref "manual-outputs-capacity-configuration") | [Assumptions](@ref "manual-outputs-capacity-assumptions") | [Examples](@ref "manual-outputs-capacity-examples") | [See Also](@ref "manual-outputs-capacity-see-also")

## [Overview](@id manual-outputs-capacity-overview)

**File:** `capacity.csv`

`capacity.csv` records the capacity of every edge and storage component in the system after the optimization. For each component, five capacity variables are reported: total optimal capacity, new capacity added in this period, capacity retired, capacity retrofitted, and existing (pre-installed) capacity at the start of the period.

This is one of the most important output files. Capacity decisions are the primary investment variables in Macro — the flows and costs all depend on the capacity choices made here.

The file uses **long format** by default: every (component, variable) combination occupies one row. However, to facilitate easier analysis of capacity breakdowns, an optional **wide format** pivots the `variable` column into separate columns for each capacity type (total, new, retired, existing, retrofitted).

## [Columns](@id manual-outputs-capacity-columns)

| Column | Type | Description |
|---|---|---|
| `commodity` | String | Commodity type carried by the component (e.g., `Electricity`, `Biomass_Wood`, `CO2`) |
| `zone` | String | Zone (location) where the component's parent asset is installed |
| `resource_id` | String | Unique identifier of the parent asset (e.g., `SE_battery`) |
| `component_id` | String | Unique identifier of the specific edge or storage component (e.g., `SE_battery_discharge_edge`) |
| `resource_type` | String | Asset type of the parent asset (e.g., `Battery`, `ThermalPower{NaturalGas}`, `VRE`) |
| `component_type` | String | Type of the component (e.g., `UnidirectionalEdge{Electricity}`, `Storage{Electricity}`) |
| `variable` | String | Which capacity metric is reported (see [Variable Types](@ref "manual-outputs-capacity-variables")) |
| `value` | Float64 | Capacity value in the system's power or energy units (default: MW or MWh) |

## [Variable Types](@id manual-outputs-capacity-variables)

The `variable` column takes one of five values, all reported for each component in the same file:

| `variable` | Description |
|---|---|
| `capacity` | Total installed capacity after the optimization: `existing + new − retired` |
| `new_capacity` | Capacity newly added during this planning period |
| `retired_capacity` | Capacity retired (decommissioned) during this planning period |
| `existing_capacity` | Capacity that was pre-installed at the start of this planning period (not a decision variable) |
| `retrofitted_capacity` | Capacity converted to a different technology via retrofitting (only non-zero when `Retrofitting = true`) |

!!! note "Retrofitting"
    `retrofitted_capacity` rows only appear when `Retrofitting = true` in `macro_settings.json`. In all other runs the row is omitted.

## [Configuration](@id manual-outputs-capacity-configuration)

| Setting | File | Default | Effect |
|---|---|---|---|
| `OutputLayout` (or `OutputLayout.Capacity`) | `macro_settings.json` | `"long"` | Set to `"wide"` to pivot the `variable` column into separate columns: `capacity`, `new_capacity`, `retired_capacity`, `existing_capacity` (and `retrofitted_capacity` if applicable). |
| `Retrofitting` | `macro_settings.json` | `false` | When `true`, a `retrofitted_capacity` row is added for each component. |

## [Assumptions](@id manual-outputs-capacity-assumptions)

- **Units** follow whatever unit system you define in your inputs. The default assumption in the Macro documentation is MW for power capacity and MWh for energy storage capacity. Capacity is reported per component (edge or storage), not per asset. A single asset may contain multiple components with separate capacity rows.
- **Components without capacity** — components with `has_capacity = false` are excluded from the output. Only components where `has_capacity = true` appear in `capacity.csv`. All storage components are always included (all storages have capacity variables by definition).
- **Multi-period models** — each period's `results_period_N/` directory contains capacity values reflecting the capacity available **during** that planning period. Per the [multi-period accounting assumptions](@ref "manual-multi-period-accounting-general-assumptions"), new capacity comes online at the **beginning** of a period. `existing_capacity` reflects the carry-over from the previous period, and `new_capacity` reflects investments made during period N.
- **Single-period models** — `existing_capacity` is the user-specified `existing_capacity` from the input data. `capacity = existing_capacity + new_capacity - retired_capacity`.
- **Capacity is reported per component, not per asset.** An asset such as a `Battery` will produce rows for each of its edges (charge, discharge) and its storage component separately. Especially for symmetric battery systems, users interested in the total installed battery capacity should typically look at the storage component or the discharge edge.

## [Examples](@id manual-outputs-capacity-examples)

### Default Long Format

| commodity | zone | resource\_id | component\_id | resource\_type | component\_type | variable | value |
|---|---|---|---|---|---|---|---|
| Electricity | SE | battery\_SE | battery\_SE\_storage | Battery | Storage{Electricity} | capacity | 200.0 |
| Electricity | SE | battery\_SE | battery\_SE\_storage | Battery | Storage{Electricity} | new\_capacity | 200.0 |
| Electricity | SE | battery\_SE | battery\_SE\_storage | Battery | Storage{Electricity} | retired\_capacity | 0.0 |
| Electricity | SE | battery\_SE | battery\_SE\_storage | Battery | Storage{Electricity} | existing\_capacity | 0.0 |

### Wide Format (`OutputLayout.Capacity = "wide"`)

| commodity | zone | resource\_id | component\_id | resource\_type | component\_type | capacity | new\_capacity | retired\_capacity | existing\_capacity |
|---|---|---|---|---|---|---|---|---|---|
| Electricity | SE | battery\_SE | battery\_SE\_storage | Battery | Storage{Electricity} | 200.0 | 200.0 | 0.0 | 0.0 |

### Writing Capacity Programmatically

- [`write_capacity`](@ref) allows you to write capacity data to a custom file path, with optional filters for commodity, asset type, or component type. This is useful for exporting subsets of the capacity data or for writing to a different location.
- [`get_optimal_capacity`](@ref) returns the capacity data as a DataFrame without writing a file. This is useful for programmatic access to capacity values within Julia.

```julia
# After solving:
(case, model) = solve_case(case_path, optimizer)

# Export capacity for a specific period/system
system = case.systems[1];
write_capacity("my_capacity.csv", system)

# Export only electricity capacity
write_capacity("elec_capacity.csv", system, commodity="Electricity")

# Export only Battery and VRE assets
write_capacity("storage_vre.csv", system, asset_type=["Battery", "VRE"])

# Get capacity as a DataFrame (no file written)
df = get_optimal_capacity(system)
```

## [See Also](@id manual-outputs-capacity-see-also)

- [Outputs Overview](@ref "manual-outputs-overview") — overview of all output files and settings
- [Costs Output](@ref "manual-outputs-costs") — investment and O&M costs associated with capacity decisions
- [Financial Assumptions](@ref "Investment costs") — how investment costs are annualized from CAPEX
- [Multi-Period Accounting](@ref "manual-multi-period-accounting-general-assumptions") — how capacity evolves across planning periods
- [Edges](@ref "manual-edges-overview") — edge investment parameters (`can_expand`, `existing_capacity`, etc.)
- [Storage](@ref "manual-storage-overview") — storage investment parameters
