# Grouped Capacity Constraints

Grouped capacity constraints bound installed or newly built capacity across a selected group of
assets. They are configured in input data, rather than in model settings, and can apply either to
the entire system or to an individual location.

Macro provides three grouped constraints:

| Constraint | Aggregated quantity | Bound |
|:--|:--|:--|
| `MaxCapacityConstraint` | total installed `capacity` | $\sum \mathrm{capacity} \leq \mathrm{value}$ |
| `MinCapacityConstraint` | total installed `capacity` | $\sum \mathrm{capacity} \geq \mathrm{value}$ |
| `MaxNewCapacityConstraint` | total `new_capacity` | $\sum \mathrm{new\_capacity} \leq \mathrm{value}$ |

## Configuration shape

Each grouped constraint uses an object payload in a `constraints` block. The keys select asset
types; each selected group specifies the asset edge field to aggregate and its limit.

```json
"<ConstraintName>": {
  "<asset-type>": {
    "edge": "<asset struct field>",
    "value": 1000.0
  }
}
```

`edge` is a field name on every selected asset, such as `"edge"` for `VRE` or `"elec_edge"` for
`ThermalPower`. The selected edge must have a capacity variable.

The object is parsed into the constraint's typed configuration object:
[`MaxCapacityConstraintConfig`](@ref), [`MinCapacityConstraintConfig`](@ref), or
[`MaxNewCapacityConstraintConfig`](@ref). The supported group keys are exactly `edge` and `value`.

!!! warning "A Boolean is not enough at system or location scope"

    Grouped constraints at system and location scope require an object payload. For example,
    `"MaxCapacityConstraint": true` is invalid because it provides no group or limit. Macro reports
    that a `MaxCapacityConstraintConfig` object is required and asks for an object payload instead.

## System-wide limits

Put system-wide grouped constraints in the top-level `constraints` block of `system_data.json`.

```json
{
  "constraints": {
    "MinCapacityConstraint": {
      "VRE": { "edge": "edge", "value": 200.0 }
    },
    "MaxCapacityConstraint": {
      "VRE": { "edge": "edge", "value": 1000.0 }
    },
    "MaxNewCapacityConstraint": {
      "VRE": { "edge": "edge", "value": 800.0 }
    }
  }
}
```

This requires at least 200 units of total VRE capacity, caps total VRE capacity at 1000, and caps
new VRE construction at 800 across the entire system. The three constraints are independent and
may be combined in one block.

## Per-location limits

Location entries may be objects with their own `constraints` block; bare location IDs remain valid.
Place the same payload below the location that should enforce it.

```json
{
  "locations": [
    {
      "id": "SE",
      "constraints": {
        "MaxCapacityConstraint": {
          "VRE": { "edge": "edge", "value": 300.0 }
        }
      }
    },
    {
      "id": "MIDAT",
      "constraints": {
        "MaxCapacityConstraint": {
          "VRE": { "edge": "edge", "value": 500.0 }
        }
      }
    },
    "NE"
  ]
}
```

System-wide and per-location limits can both be active. For example, total VRE capacity can be at
most 1000 while VRE capacity in `SE` is independently limited to 300.

For a per-location group, Macro finds an edge's location in this order: the edge's own `location`,
its end vertex's location, then its start vertex's location. Assets outside the configured location
do not contribute to that group's expression.

## Selecting assets

The group key selects assets by type. A defined Julia asset type uses subtype matching; exact
parametric names and wildcard selectors use type-string matching.

| Group key | Matches |
|:--|:--|
| `"VRE"` | all VRE technologies, including `VRE{Generic}` |
| `"VRE{Solar}"` | only solar VRE assets |
| `"ThermalPower"` | all commodity variants of `ThermalPower` |
| `"ThermalPower{NaturalGas}"` | only natural-gas thermal-power assets |
| `"Battery"` | Battery assets |
| `"VRE*"` | asset types beginning with `VRE` |

An asset type that matches no assets produces a warning and no constraint for that group. A group
that has no matching assets in a configured location is skipped. If a selected asset lacks the
specified edge field, Macro reports an error; if the field has no capacity variable, that asset is
skipped with a warning.

## Parameter scaling

Group `value`s are capacity quantities. When `ParameterScaling` is enabled, Macro divides them by
`ParameterScalingFactor` before solving and restores their original values after the solve. This
keeps grouped limits consistent with the scaled capacity and new-capacity variables.
