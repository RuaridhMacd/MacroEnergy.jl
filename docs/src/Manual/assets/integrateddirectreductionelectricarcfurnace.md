# DrEaf (with and without CCS)

## Contents

[Overview](@ref "dreaf_overview") | [Asset Structure](@ref "dreaf_asset_structure") | [Flow Equations](@ref "dreaf_flow_equations") | [Input File (Standard Format)](@ref "dreaf_input_file") | [Types - Asset Structure](@ref "dreaf_type_definition") | [Constructors](@ref "dreaf_constructors") | [Examples](@ref "dreaf_examples")

## [Overview](@id "dreaf_overview")

In Macro, DrEaf represents integrated steelmaking facilities that combine direct reduction (DR) units with electric arc furnaces (EAF). In these configurations, iron ore is initially reduced in a direct reduction reactor, using either natural gas or hydrogen, to produce hot direct reduced iron (hDRI), which is subsequently processed into crude steel in electric arc furnaces. 
These assets are specified via input files in JSON or CSV format, located in the assets directory, and are typically named with descriptive identifiers such as hydrogen_dr_eaf.json or hydrogen_dr_eaf.csv.

## [Asset Structure](@id "dreaf_asset_structure")

A DR-EAF plant (with and without CCS) is made of the following components:
- 1 `Transformation` component, representing the DR-EAF (with and without CCS).
- 8 `Edge` components:
    - 1 **incoming** `IronOre Edge`, representing the supply of iron ore of a suitable grade for direct reduction, represented by the IronOreDR commodity. 
    - 1 **incoming** `Reductant Edge`, representing the supply of the reductant, which can be natural gas or hydrogen.
    - 1 **incoming** `Electricity Edge`, representing the supply of electricity.
    - 1 **incoming** `Metcoal Edge`, representing the supply of metallurgical coal. **(only if hydrogen is used as a reductant, metallurgical coal provides the necessary carbon for the steel)**.
    - 1 **outgoing** `CrudeSteel Edge`, representing the crude steel production.
    - 1 **outgoing** `CO2 Edge`, representing the CO2 that is emitted.
    - 1 **outgoing** `CO2Captured Edge`, representing the CO2 that is captured **(only if CCS is present)**.
      
Here is a graphical representation of the NG-DR-EAF asset without CCS:

```mermaid
%%{init: {'theme': 'base', 'themeVariables': { 'background': '#D1EBDE' }}}%%
flowchart BT
  subgraph NG-DR-EAF
  direction BT
    A1(("**Iron Ore**")) e1@-->B{{"**NG-DR-EAF**"}}
    A2(("**NaturalGas**")) e2@-->B{{"**NG-DR-EAF**"}}
    A3(("**Electricity**")) e3@-->B{{"**NG-DR-EAF**"}}
    B{{"**NG-DR-EAF**"}} e4@-->C1(("**Crude Steel**"))
    B{{"**NG-DR-EAF**"}} e5@-->C2(("**CO2**"))

    e1@{ animate: true }
    e2@{ animate: true }
    e3@{ animate: true }
    e4@{ animate: true }
    e5@{ animate: true }
 end
    style A1 font-size:15px,r:45px,fill:#FFD700D,stroke:black,color:black,stroke-dasharray: 3,5;
    style A2 font-size:15px,r:45px,fill:#005F6A,stroke:black,color:black,stroke-dasharray: 3,5;
    style A3 font-size:15px,r:45px,fill:#FFD700,stroke:black,color:black,stroke-dasharray: 3,5;
    style B fill:white,stroke:black,color:black;
    style C1 font-size:15px,r:45px,fill:#696969,stroke:black,color:black,stroke-dasharray: 3,5;
    style C2 font-size:15px,r:45px,fill:lightgray,stroke:black,color:black,stroke-dasharray: 3,5;

    linkStyle 0,1 stroke:#FFD700D, stroke-width: 2px;
    linkStyle 1,2 stroke:#005F6A, stroke-width: 2px;
    linkStyle 2,3 stroke:#FFD700, stroke-width:2px;
    linkStyle 3,4 stroke:#696969, color:lightgray, stroke-width: 2px;

```
## [Flow Equations](@id "dreaf_flow_equations")

The integrated DR-EAF asset follows these stoichiometric relationships:

```math
\begin{aligned}
\phi_{ironore} &= \phi_{crudesteel} \cdot \epsilon_{ironore\_consumption} \\
\phi_{fuel} &= \phi_{crudesteel} \cdot \epsilon_{fuel\_consumption} \\
\phi_{elec} &= \phi_{crudesteel} \cdot \epsilon_{elec\_consumption} \\
\phi_{metcoal} &= \phi_{crudesteel} \cdot \epsilon_{metcoal\_consumption} \quad \text{(if hydrogen is the reductant)} \\
\phi_{co2} &= \phi_{crudesteel} \cdot \epsilon_{emission\_rate} \\
\phi_{co2\_captured} &= \phi_{crudesteel} \cdot \epsilon_{co2\_capture\_rate} \quad \text{(if CCS)} \\
\end{aligned}
```
Where:
- $\phi$ represents the flow of each commodity.
- $\epsilon$ represents the stoichiometric coefficients defined in the [Conversion Process Parameters](@ref "dreaf_conversion_process_parameters") section.

## [Input File (Standard Format)](@id "dreaf_input_file")

The easiest way to include an integrated DR-EAF asset in a model is to create a new file (either JSON or CSV) and place it in the `assets` directory together with the other assets. 

```
your_case/
├── assets/
│   ├── natural_gas_dr_eaf.json    # or natural_gas_dr_eaf.csv
│   ├── other_assets.json
│   └── ...
├── system/
├── settings/
└── ...
```

This file can either be created manually or using the `template_asset` function, as shown in the [Adding an Asset to a System](@ref) section of the User Guide. The file will be automatically loaded when you run your Macro model. An example of an input JSON file is shown in the [Examples](@ref "dreaf_examples") section.

The following tables outline the attributes that can be set for a DrEaf.

### Transform Attributes
#### Essential Attributes
| Field | Type | Description |
|--------------|---------|------------|
| `Type` | String | Asset type identifier: "DrEaf" |
| `id` | String | Unique identifier for the asset instance |
| `location` | String | Geographic location/node identifier |
| `timedata` | String | Time resolution for the time series data linked to the transformation |

#### [Conversion Process Parameters](@id "dreaf_conversion_process_parameters")
| Field | Type | Description | Units | Default |
|--------------|---------|------------|----------------|----------|
| `ironore_consumption` | Float64 | iron ore consumption per ton of crude steel output | $t_{ironore}/t_{crudesteel}$ | 0.0 |
| `reductant_consumption` | Float64 | reductant consumption per ton of crude steel output | $MWh/t_{crudesteel}$ | 0.0 |
| `electricity_consumption` | Float64 | electricity consumption per ton of crude steel output | $MWh_{elec}/t_{crudesteel}$ | 0.0 |
| `metcoal_consumption` | Float64 | metallurgical coal consumption per ton of crude steel output | $t/t_{crudesteel}$ | 0.0 |
| `emission_rate` | Float64 | CO2 emissions  per ton of crude steel output | $t_{CO2}/t_{crudesteel}$ | 0.0 |
| `capture_rate` | Float64 | captured CO2 emissions  per ton of crude steel output | $t_{CO2}/t_{crudesteel}$ | 0.0 |

### Edges

The definition of the `Edge` object can be found here [MacroEnergy.Edge](@ref).

#### General Attributes

| Field | Type | Values | Default | Description |
|:--------------| :------: |:------: | :------: |:-------|
| `type` | `String` | Any Macro commodity type matching the commodity of the edge | Required | Commodity of the edge. E.g. "Electricity". |
| `start_vertex` | `String` | Any node id present in the system matching the commodity of the edge | Required | ID of the starting vertex of the edge. The node must be present in the `nodes.json` file. E.g. "elec\_node\_1". |
| `end_vertex` | `String` | Any node id present in the system matching the commodity of the edge | Required | ID of the ending vertex of the edge. The node must be present in the `nodes.json` file. E.g. "crudesteel\_node\_1". |
| `availability` | `Dict` | Availability file path and header | Empty | Path to the availability file and column name for the availability time series to link to the edge. E.g. `{"timeseries": {"path": "assets/availability.csv", "header": "DrEaf"}}`.|
| `has_capacity` | `Bool` | `Bool` | `false` | Whether capacity variables are created for the edge. |
| `integer_decisions` | `Bool` | `Bool` | `false` | Whether capacity variables are integers. |
| `unidirectional` | `Bool` | `Bool` | `false` | Whether the edge is unidirectional. |

!!! warning "Asset expansion"
    As a modeling decision, only the `CrudeSteel` is allowed to expand. Therefore, both the `has_capacity` and `constraints` attributes can only be set for that edge. For all other edges, these attributes are pre-set to `false` and an empty list, respectively, to ensure the correct modeling of the asset. 

!!! warning "Directionality"
    The `unidirectional` attribute is set to `true` for all the edges.

#### Investment Parameters
| Field | Type | Description | Units | Default |
|--------------|---------|------------|----------------|----------|
| `can_retire` | Boolean | Whether capacity can be retired | - | true |
| `can_expand` | Boolean | Whether capacity can be expanded | - | true |
| `existing_capacity` | Float64 | Initial installed capacity | tCrudeSteel/hr | 0.0 |

#### Economic Parameters
| Field | Type | Description | Units | Default |
|--------------|---------|------------|----------------|----------|
| `investment_cost` | Float64 | CAPEX per unit capacity | \$/tCrudeSteel/hr | 0.0 |
| `fixed_om_cost` | Float64 | Fixed O&M costs | \$/tCrudeSteel/hr | 0.0 |
| `variable_om_cost` | Float64 | Variable O&M costs | \$/tCrudeSteel | 0.0 |

### [Constraints Configuration](@id "dreaf_constraints")

DrEaf assets can have different constraints applied to them, and the user can configure them using the following fields:

| Field | Type | Description |
|--------------|---------|------------|
| `transform_constraints` | Dict{String,Bool} | List of constraints applied to the transformation component. |
| `output_constraints` | Dict{String,Bool} | List of constraints applied to the output edge component. |

For example, if the user wants to apply the [`BalanceConstraint`](@ref "balance_constraint_ref") to the transformation component and the [`MaxCapacityConstraint`](@ref "max_capacity_constraint_ref") to the output edge, the constraints fields should be set as follows:

```json
{
    "transform_constraints": {
        "BalanceConstraint": true
    },
    "edges":{
        "crudesteel_edge": {
            "constraints": {
                "MaxCapacityConstraint": true
            }
        }
}
```

Users can refer to the [Adding Asset Constraints to a System](@ref) section of the User Guide for a list of all the constraints that can be applied to the different components of a DrEaf asset.

#### Default constraints
To simplify the input file and the asset configuration, the following constraints are applied to the DrEaf asset by default:

- [Balance constraint](@ref "balance_constraint_ref") (applied to the transformation component)
- [Capacity constraint](@ref "capacity_constraint_ref") (applied to the output crude steel edge)
- [MustRun constraint](@ref "mustrun_constraint_ref") (applied to the output crude steel edge)

## [Types - Asset Structure](@id "dreaf_type_definition")

The DrEaf asset is defined as follows:

```julia
struct DrEaf{T} <: AbstractAsset
    id::AssetId
    dreaf_transform::Transformation
    crudesteel_edge::Edge{CrudeSteel}
    reductant_edge::Edge{T}
    elec_edge::Edge{Electricity}
    metcoal_edge::Edge{MetCoal}
    ironore_edge::Edge{IronOreDR}
    co2_edge::Edge{CO2}
end
```
Here, T denotes the reductant, which may be either natural gas or hydrogen.

## [Constructors](@id "dreaf_constructors")

### Factory constructor
```julia
make(asset_type::Type{DrEaf}, data::AbstractDict{Symbol,Any}, system::System)
```

| Field | Type | Description |
|--------------|---------|------------|
| `asset_type` | `Type{DrEaf}` | Macro type of the asset |
| `data` | `AbstractDict{Symbol,Any}` | Dictionary containing the input data for the asset |
| `system` | `System` | System to which the asset belongs |

### Stochiometry balance data
```julia
dreaf_transform.balance_data = Dict(
        :ironore_consumption=> Dict(
            crudesteel_edge.id => get(transform_data, :ironore_consumption, 0.0),
            ironore_edge.id => 1.0
        ),
        :electricity_consumption => Dict(
            crudesteel_edge.id => get(transform_data, :electricity_consumption, 0.0),
            elec_edge.id => 1.0
        ),
        :reductant_consumption => Dict(
            crudesteel_edge.id => get(transform_data, :reductant_consumption, 0.0),
            reductant_edge.id => 1.0
        ),
        :metcoal_consumption => Dict(
            crudesteel_edge.id => get(transform_data, :metcoal_consumption, 0.0),
            metcoal_edge.id => 1.0
        ),
        :emissions => Dict(
            crudesteel_edge.id => get(transform_data, :emission_rate, 0.0),
            co2_edge.id => -1.0,
        ),
)
```
!!! warning "Dictionary keys must match"
    In the code above, each `get` function call looks up a parameter in the `transform_data` dictionary using a symbolic key such as `:reductant_consumption` or `:emission_rate`.
    These keys **must exactly match** the corresponding field names in your input asset `.json` or `.csv` files. Mismatched key names between the constructor file and the asset input will result in missing or incorrect parameter values (defaulting to `0.0`).
    

## [Examples](@ref "dreaf_examples")

This example illustrates a basic DrEaf configuration using hydrogen as a reductant in JSON format, featuring standard parameters in a three-zone case.


```json
{
    "hydrogen_dr_eaf": [
        {
            "type": "DrEaf",
            "global_data":{
                "nodes": {},
                "transforms": {
                    "timedata": "Hydrogen",
                    "constraints": {
                            "BalanceConstraint": true
                    }
                },
                "edges":{
                    "crudesteel_edge": {
                        "commodity": "CrudeSteel",
                        "unidirectional": true,
                        "has_capacity": true,
                        "can_retire": true,
                        "can_expand": true,
                        "integer_decisions": false,
                        "constraints": {
                            "CapacityConstraint": true
                        }
                    },
                    "reductant_edge": {
                        "commodity": "Hydrogen",
                        "unidirectional": true,
                        "has_capacity": false
                    },
                    "ironore_edge":{
                        "commodity": "IronOreDR",
                        "unidirectional": true,
                        "has_capacity": false
                    },
                    "elec_edge":{
                        "commodity": "Electricity",
                        "unidirectional": true,
                        "has_capacity": false
                    },
                    "metcoal_edge": {
                        "commodity": "MetCoal",
                        "unidirectional": true,
                        "has_capacity": false
                    },
                    "co2_edge": {
                        "commodity": "CO2",
                        "unidirectional": true,
                        "has_capacity": false,
                        "end_vertex": "co2_sink_steel"
                    }
                }
            },
            "instance_data":[
                {
                    "id": "SE_hydrogen_dr_eaf",
                    "transforms":{
                        "ironore_consumption": 1.59,
                        "reductant_consumption": 2.43,
                        "electricity_consumption": 1.66,
                        "metcoal_consumption": 0.03,
                        "emission_rate": 0.08
                    },
                    "edges":{
                            "crudesteel_edge": {
                                "end_vertex": "crudesteel_SE",
                                "existing_capacity": 0.0,
                                "investment_cost": 6973921,
                                "fixed_om_cost": 139478,
                                "variable_om_cost": 135
                            },
                            "reductant_edge": {
                                "start_vertex": "h2_SE"
                            },
                            "elec_edge":{
                                "start_vertex": "elec_SE"
                            },
                            "ironore_edge":{
                                "start_vertex": "ironoredr_source"
                            },
                            "metcoal_edge": {
                                "start_vertex": "metcoal_source"
                            }
                        }
                },
                {
                    "id": "MIDAT_hydrogen_dr_eaf",
                    "transforms":{
                       "ironore_consumption": 1.59,
                        "reductant_consumption": 2.43,
                        "electricity_consumption": 1.66,
                        "metcoal_consumption": 0.03,
                        "emission_rate": 0.08
                    },
                    "edges":{
                            "crudesteel_edge": {
                                "end_vertex": "crudesteel_MIDAT",
                                "existing_capacity": 0.0,
                                "investment_cost": 6973921,
                                "fixed_om_cost": 139478,
                                "variable_om_cost": 135
                            },
                            "reductant_edge": {
                                "start_vertex": "h2_MIDAT"
                            },
                            "elec_edge":{
                                "start_vertex": "elec_MIDAT"
                            },
                            "ironore_edge":{
                                "start_vertex": "ironoredr_source"
                            },
                            "metcoal_edge": {
                                "start_vertex": "metcoal_source"
                            }
                        }
                },
                {
                    "id": "NE_hydrogen_dr_eaf",
                    "transforms":{
                        "ironore_consumption": 1.59,
                        "reductant_consumption": 2.43,
                        "electricity_consumption": 1.66,
                        "metcoal_consumption": 0.03,
                        "emission_rate": 0.08
                    },
                    "edges":{
                            "crudesteel_edge": {
                                "end_vertex": "crudesteel_NE",
                                "existing_capacity": 0.0,
                                "investment_cost": 6973921,
                                "fixed_om_cost": 139478,
                                "variable_om_cost": 135
                            },
                            "reductant_edge": {
                                "start_vertex": "h2_NE"
                            },
                            "elec_edge":{
                                "start_vertex": "elec_NE"
                            },
                            "ironore_edge":{
                                "start_vertex": "ironoredr_source"
                            },
                            "metcoal_edge": {
                                "start_vertex": "metcoal_source"
                            }
                        }
                }

            ]
        }
    ]
}
```
