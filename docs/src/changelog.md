<!-- This file is generated from CHANGELOG.md by docs/scripts/update_changelog.jl. -->

# Changelog

All notable changes to MacroEnergy.jl will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows Julia package versioning through `Project.toml` releases.

## [Unreleased]

## [0.1.0] - 2026-04-14

### Added

- Expanded result writing and postprocessing for non-served demand, storage level, curtailment, time weights, discounted and undiscounted cost outputs, and detailed cost breakdowns.
- Added full time-series reconstruction across Monolithic, Myopic, and Benders workflows through `WriteFullTimeseries`.
- Added `SyntheticAmmonia`, `SyntheticMethanol`, `ThermalAmmonia`, `ThermalAmmoniaCCS`, `ThermalMethanol`, `ThermalMethanolCCS`, and `OneWayTransmissionLink` assets.
- Added `StorageChargeLimitConstraint`, long-duration storage feasibility constraints for Benders, and additional storage safety checks.
- Added Myopic restart support, `StopAfterPeriod`, optional JuMP direct-model generation, optional string names, updated default HiGHS settings, and economic utilities for present-value and cash-flow calculations.

### Changed

- Redesigned node supply inputs around named supply dictionaries with per-segment `price`, `min`, and `max` values.
- Split edge types into explicit unidirectional and bidirectional forms.
- Changed `TransmissionLink` to model bidirectional transfer; use `OneWayTransmissionLink` for one-way transfer.
- Cleaned up user extension loading through the `user_additions/` layout.
- Renamed emissions-tracking assets to `UpstreamEmissions` and `DownstreamEmissions`, with compatibility aliases for older names.
- Expanded documentation and tests for TimeData, timeseries outputs, retrofitting, run workflows, outputs, constraints, assets, transmission links, supply parsing, and user additions.

### Removed

- Removed legacy unified output code in favor of the expanded `write_*` output suite.

### Fixed

- Improved Benders output parity and cost handling by performing a final operational solve for the selected planning solution.
- Fixed and improved transmission, storage, dual, cost, and documentation behavior across the release.

## [0.0.3] - 2025-11-21

### Added

- Added iron and steel sector assets and documentation.
- Added heat and steam sector commodities, assets, examples, and documentation.
- Added aluminum sector default real-world parameters.
- Added output support for dual values from `BalanceConstraint` and `CO2CapConstraint`.
- Added minimum retired capacity tracking and extended retrofit features to multi-stage models.
- Added Windows coverage to CI.

### Changed

- Updated installation instructions, citation metadata, asset library docs, modeler debugging docs, and timeseries documentation.

### Fixed

- Fixed several Windows-related path and user-additions issues.
- Fixed retrofit integer decisions, hydropower reservoir efficiency handling, documentation cross references, and Benders dual scaling behavior.

## [0.0.2] - 2025-09-25

### Added

- Added logging options.
- Added settings output in results.
- Added automatic Mermaid diagrams for assets.
- Added asset retrofits for single-stage cases.
- Added options to free model memory and write myopic outputs during iterations.

### Changed

- Refactored output-writing utilities.

### Fixed

- Fixed subcommodity loading.

## [0.0.1] - 2025-08-20

### Added

- Initial registered release of MacroEnergy.jl.

[Unreleased]: https://github.com/macroenergy/MacroEnergy.jl/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/macroenergy/MacroEnergy.jl/compare/v0.0.3...v0.1.0
[0.0.3]: https://github.com/macroenergy/MacroEnergy.jl/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/macroenergy/MacroEnergy.jl/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/macroenergy/MacroEnergy.jl/releases/tag/v0.0.1
