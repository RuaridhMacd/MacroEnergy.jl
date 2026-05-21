# Macro

**Macro** is a bottom-up, multi-sectoral infrastructure optimization model for macro-energy systems. It co-optimizes the design and operation of user-defined models of multi-sector energy systems and networks. Macro allows users to explore the impact of changing energy policies, technologies, demand patterns, and other factors on an energy system as a whole and as separate sectors.

## Features

The Macro development team have built on their experience developing the [GenX](https://github.com/GenXProject/GenX.jl) and [Dolphyn](https://github.com/macroenergy/Dolphyn.jl) models to develop a new architecture which is easier and faster to expand to new energy technologies, policies, and sectors.

Macro's key features are:

- **Graph-based representation** of the energy system, facilitating clear representation and analysis of energy and mass flows between sectors.
- **"Plug and play" flexibility** for integrating new technologies and sectors, including electricity, hydrogen, heat, and transport.
- **High spatial and temporal resolution** to accurately capture sector dynamics.
- Designed for **distributed computing** to enable large-scale optimizations.
- Tailored **Benders decomposition** framework for optimization.
- **Open-source** built using Julia and JuMP.

## Citing Macro

If you use Macro, please cite the current version of the software and the software paper.

The version citation is available in the "About" section of the GitHub repository.

We have submitted a peer-reviewed paper describing Macro, but please cite the preprint in the meantime:

```bibtex
@article{macdonald2025macroenergy,
  title={MacroEnergy. jl: A large-scale multi-sector energy system framework},
  author={Macdonald, Ruaridh and Pecci, Filippo and Bonaldo, Luca and Law, Jun Wen and Weng, Yu and Mallapragada, Dharik and Jenkins, Jesse},
  journal={arXiv preprint arXiv:2510.21943},
  year={2025}
}
```

## Installation

You can install Macro (aka.MacroEnergy.jl) using the Julia package manager:

```julia
using Pkg
Pkg.add("MacroEnergy")
```

If you wish to make additons to Macro, please follow the installation instructions in the documentation, [on the Getting Started / Installation page.](https://macroenergy.github.io/MacroEnergy.jl/dev/Getting%20Started/2_installation/)

## Recent changes

<!-- BEGIN GENERATED RECENT CHANGES -->
### 0.1.0 - 2026-04-14
#### Added

- Expanded result writing and postprocessing for non-served demand, storage level, curtailment, time weights, discounted and undiscounted cost outputs, and detailed cost breakdowns.
- Added full time-series reconstruction across Monolithic, Myopic, and Benders workflows through `WriteFullTimeseries`.
- Added `SyntheticAmmonia`, `SyntheticMethanol`, `ThermalAmmonia`, `ThermalAmmoniaCCS`, `ThermalMethanol`, `ThermalMethanolCCS`, and `OneWayTransmissionLink` assets.
- Added `StorageChargeLimitConstraint`, long-duration storage feasibility constraints for Benders, and additional storage safety checks.
- Added Myopic restart support, `StopAfterPeriod`, optional JuMP direct-model generation, optional string names, updated default HiGHS settings, and economic utilities for present-value and cash-flow calculations.

#### Changed

- Redesigned node supply inputs around named supply dictionaries with per-segment `price`, `min`, and `max` values.
- Split edge types into explicit unidirectional and bidirectional forms.
- Changed `TransmissionLink` to model bidirectional transfer; use `OneWayTransmissionLink` for one-way transfer.
- Cleaned up user extension loading through the `user_additions/` layout.
- Renamed emissions-tracking assets to `UpstreamEmissions` and `DownstreamEmissions`, with compatibility aliases for older names.
- Expanded documentation and tests for TimeData, timeseries outputs, retrofitting, run workflows, outputs, constraints, assets, transmission links, supply parsing, and user additions.

#### Removed

- Removed legacy unified output code in favor of the expanded `write_*` output suite.

#### Fixed

- Improved Benders output parity and cost handling by performing a final operational solve for the selected planning solution.
- Fixed and improved transmission, storage, dual, cost, and documentation behavior across the release.

#### Migration guide

- Update node supply inputs to the named `supply` dictionary format. Each supply segment should define `price`, `min`, and `max` values. Legacy `price_supply` and `max_supply` inputs are still handled, and `update_node_supply_inputs(...)` can help convert existing cases.
- Review any cases using automatically generated supply segment names. Segment names now use `segment1`, `segment2`, and so on.
- Review transmission assets. `TransmissionLink` is now bidirectional by default; use `OneWayTransmissionLink` when directionality matters.
- Update any direct use of edge types to the explicit unidirectional and bidirectional edge forms.
- Update output-processing scripts that relied on the legacy unified output code. Use the expanded `write_*` output functions instead.
- Review models that assumed nodes did not include balance constraints by default. Nodes now have `BalanceConstraint` enabled by default.
- Prefer the renamed emissions assets `UpstreamEmissions` and `DownstreamEmissions`. Compatibility aliases remain for older names, including `FossilFuelsUpstream` and `FuelsEndUse`.

For the full release history, see [CHANGELOG.md](CHANGELOG.md).
<!-- END GENERATED RECENT CHANGES -->
## Learning to use Macro

### Documentation

The Macro documentation [can be found here.](https://macroenergy.github.io/MacroEnergy.jl/). The documentation contains five main resources:

- A getting started section, which shows you how to install and run Macro.
- Guides, which walk you through how to achieve specfic tasks using Macro.
- A manual, which describes all the components and features of Macro in detail.
- Tutorials, which are extended guides with worked examples
- A function reference, which etails the API and functions available with Macro.

### Bug reports

Please report any bugs or new feature requrests on [the Issues page of this repository](https://github.com/macroenergy/MacroEnergy.jl/issues).
