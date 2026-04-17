# Decomposition Implementation Plan

## Purpose

This document is the working implementation plan for introducing the new decomposition architecture on top of the current `decomposition-architecture-scaffold` branch.

It is intended to preserve context across sessions while we migrate from the current stateful `System` plus ad hoc Benders workflow toward:

```text
StaticSystem -- ProblemSpec --> ProblemInstance
```

The design goals are described in `docs/planning/decomposition_architecture.md`.
This document is the staged execution plan for getting there.

## Scope

Initial scope:

- monolithic solves
- temporal Benders only
- preserve current behavior where practical
- avoid structural rebuilds of subproblem models across Benders iterations

Deferred scope:

- spatial decomposition builders
- sectoral decomposition builders
- mixed decompositions
- GPU batch solve integration

## Current Baseline In This Repo

Today, the main code paths are still built around the older mutable layout:

- `src/model/system.jl` stores `System`
- `src/model/networks/node.jl` stores JuMP refs directly on `Node`
- `src/model/networks/edge.jl` stores JuMP refs directly on `Edge` and `EdgeWithUC`
- `src/model/networks/storage.jl` stores JuMP refs directly on `Storage` and `LongDurationStorage`
- `src/model/generate_model.jl` builds models by mutating those objects in place
- `src/model/benders/planning.jl` builds the planning model in the legacy style
- `src/model/benders/operations.jl` builds temporal Benders subproblems as `Dict`s containing `:model`, `:system_local`, and linking-variable names
- `src/model/benders/prepare_benders_run.jl` creates temporal decomposition by `deepcopy(system)`

This means the first migration steps should introduce the new abstractions beside the old ones, not attempt a single rewrite.

## Stage Overview

### Stage 0: Establish Ground Truth

Goal:

- make sure we have stable tests and a migration note before deeper refactors

Key files:

- `docs/planning/decomposition_architecture.md`
- `test/`

Exit criteria:

- architecture note exists and reflects current decisions
- at least one focused test exists for the new architecture scaffolding

Status:

- complete

Notes:

- `test/test_problem_architecture.jl` now covers `StaticSystem`, default `ProblemSpec`, and `ProblemInstance` creation

### Stage 1: Introduce Core Scaffolding

Goal:

- add the first version of the new architecture types without changing solver behavior yet

Key files:

- `src/model/problems/static_system.jl`
- `src/model/problems/problem_spec.jl`
- `src/model/problems/local_state.jl`
- `src/model/problems/update_map.jl`
- `src/model/problems/reassembly_map.jl`
- `src/model/problems/problem_instance.jl`
- `src/MacroEnergy.jl`

Exit criteria:

- `StaticSystem(system::System)` exists
- `ProblemSpec` and `normalize_problem_spec` exist
- `ProblemInstance` exists
- `UpdateMap` and `ReassemblyMap` exist
- types are exported and covered by a focused test

Status:

- complete

Notes:

- `StaticSystem` currently normalizes the existing loaded `System` into typed stores
- this is still read-only scaffolding and does not yet drive model generation

### Stage 2: Route Monolithic Build Through The New Problem Layer

Goal:

- make monolithic build consume `StaticSystem` and normalized `ProblemSpec` internally
- preserve the public `generate_model(case, opt)` and `solve_case` APIs

Key files:

- `src/model/generate_model.jl`
- `src/model/solver.jl`
- `src/model/problems/problem_instance.jl`
- new builder file(s), likely `src/model/problems/build.jl`

Planned work:

- add a problem builder for full monolithic problems
- construct one `ProblemInstance` per monolithic solve
- keep returning `Model` to existing callers
- initially allow builder internals to materialize local problem-owned state while preserving current output paths

Exit criteria:

- monolithic solve still works through the public API
- monolithic build goes through `StaticSystem` plus normalized `ProblemSpec`
- current monolithic tests continue to pass

Risks:

- many helper functions currently assume field-backed state directly on `Node`, `Edge`, and `Storage`
- the first monolithic integration may need compatibility adapters rather than a full local-state rewrite

Status:

- mostly complete

Notes:

- `generate_model(case, opt)` now routes through `build_monolithic_model(case, opt)`
- monolithic periods are currently represented as one `ProblemInstance` per period
- carry-over and retrofit logic now run through `ProblemInstance`-based helpers
- `StaticSystem` no longer keeps a back-reference to the source `System`
- Myopic model construction now reuses the same problem-layer build path as monolithic
- focused regression checks currently pass for monolithic model generation and a one-period Myopic run
- small automated regressions now cover multi-period case loading plus monolithic/Myopic builder paths; full example runs remain the best higher-level validation

Stage 2 exit checklist:

- monolithic multi-period solve still works through `solve_case(case, opt)`
- Myopic multi-period solve still works through `solve_case(case, opt)`
- monolithic and Myopic model construction do not rely on `System`-specific model-build helpers
- inter-period carry-over during monolithic and Myopic solve paths is driven by `ProblemInstance`-based helpers

Remaining intentional compatibility shims before Stage 3:

- case loading and preparation still construct legacy `System`s
- Myopic restart-from-results still writes capacities back into a `System`
- output writing still reads solved values from the legacy `System` view

### Stage 3: Create Explicit Planning And Temporal Subproblem Builders

Goal:

- replace the legacy ad hoc planning/subproblem construction path with builder-based `ProblemInstance`s

Key files:

- `src/model/benders/planning.jl`
- `src/model/benders/operations.jl`
- `src/model/benders/prepare_benders_run.jl`
- `src/model/problems/problem_spec.jl`
- `src/model/problems/problem_instance.jl`

Planned work:

- define planning `ProblemSpec`s
- define temporal subproblem `ProblemSpec`s
- replace `deepcopy(system)` temporal decomposition with spec generation
- build persistent temporal subproblem `ProblemInstance`s

Status:

- in progress

Notes:

- a general `problem_spec(...)` constructor now drives planning and temporal subproblem specs
- planning problem construction now uses planning-period `ProblemInstance`s internally
- temporal Benders subproblems are now built as persistent `ProblemInstance`s wrapped in a legacy adapter dict
- the legacy adapter still exposes `:model`, `:linking_variables_sub`, `:subproblem_index`, and `:system_local` for solver and output compatibility
- temporal subproblem instances now populate a first real `UpdateMap` of direct linking-variable fix updates
- the final subproblem resolve path now applies planning solutions through `ProblemInstance.update_map` and re-solves the same persistent models in place
- Benders output utilities can now read directly from `ProblemInstance.static_system` for subproblem extraction, slack collection, and balance-dual collection
- focused builder checks currently pass for planning problem generation, serial subproblem initialization, and repeated in-place fix updates on `test/test_small_case`

Exit criteria:

- planning problem is represented as a `ProblemInstance`
- each temporal subproblem is represented as a persistent `ProblemInstance`
- legacy `Dict`-style subproblem containers are no longer the primary internal representation

Risks:

- `MacroEnergySolvers.benders` currently expects `Dict`-style subproblem containers
- a temporary adapter layer will likely be needed

### Stage 4: Introduce In-Place Update Infrastructure

Goal:

- make temporal subproblem instances persistent across Benders iterations and update them in place

Key files:

- `src/model/problems/update_map.jl`
- `src/model/benders/operations.jl`
- `src/model/benders/results.jl`
- adapter code around `MacroEnergySolvers`

Planned work:

- add concrete `UpdateInstruction`s for fixing linking variables, changing bounds, and updating RHS values
- populate `UpdateMap` during subproblem build
- apply updates in place before each subproblem solve
- avoid any structural rebuild across Benders iterations

Status:

- in progress

Exit criteria:

- subproblem models are built once
- repeated Benders iterations only apply cheap in-place updates
- temporal Benders behavior matches current behavior closely

Risks:

- current external solver package is variable-name based
- updates may need to bridge between local typed metadata and current name-based interfaces at first

Notes:

- `UpdateMap` currently covers linking-variable fix updates only
- main Benders iterations still rely on the legacy `MacroEnergySolvers` string-name update path
- this is intentional temporary compatibility; the explicit in-place update path now exists on the `MacroEnergy.jl` side and is already used for the final subproblem resolve

### Stage 5: Move Result Reconstruction To ReassemblyMap

Goal:

- reconstruct global flows, storage levels, NSD, and duals from local subproblem state using `ReassemblyMap`

Key files:

- `src/model/problems/reassembly_map.jl`
- `src/write_outputs/utilities/benders_output_utilities.jl`
- `src/write_outputs/write_outputs.jl`

Planned work:

- define how local component-time slices map back into global outputs
- stop relying on `:system_local` deep-copied systems for result extraction
- use `ReassemblyMap` plus local state to assemble outputs

Status:

- in progress

Exit criteria:

- Benders output utilities can read from `ProblemInstance`s
- global result reconstruction no longer depends on cloned `System`s

Risks:

- current write/output utilities assume canonical component objects carry solved JuMP refs or values

Notes:

- Benders output utilities now prefer `ProblemInstance.static_system` when available
- slack-variable and balance-dual collection no longer require `:system_local` if `:problem_instance` is present
- `ProblemInstance` build now populates `ReassemblyMap` slices for selected components
- node-level slack and balance-dual collection now uses `ReassemblyMap` to remap local time indices back to global time indices
- operational subproblem result extraction for flows, storage levels, non-served demand, and curtailment now uses `ProblemInstance` plus `ReassemblyMap`
- active initialized Benders subproblem dicts no longer carry `:system_local`; the legacy field remains supported only as a fallback for older tests and compatibility helpers
- temporal subproblem bundles no longer carry the copied subproblem `System` wrapper; the active path keeps only `ProblemInstance` plus metadata
- full global result reconstruction still needs explicit `ReassemblyMap` usage before this stage can be considered complete

### Stage 6: Reduce Reliance On Shared Component-Owned Solve State

Goal:

- move from “new architecture wrapped around old mutable components” to “problem-owned local solve state”

Key files:

- `src/model/networks/node.jl`
- `src/model/networks/edge.jl`
- `src/model/networks/storage.jl`
- `src/model/networks/transformation.jl`
- builder files under `src/model/problems/`

Planned work:

- shift model refs, expression refs, and solved values into `NodeLocalState`, `EdgeLocalState`, `StorageLocalState`, and `TransformationLocalState`
- keep static component objects shared across problems
- retain compatibility shims where needed during transition

Status:

- in progress

Exit criteria:

- shared static objects no longer need to own one live JuMP state
- simultaneous planning and subproblem instances can coexist cleanly

Risks:

- this is the most invasive stage and should only happen after monolithic and temporal Benders are stable on the new architecture

Notes:

- `ProblemInstance` population now synchronizes currently-built JuMP refs and expressions into local state dictionaries
- temporal subproblem generation now performs that local-state sync after operation model construction
- persistent subproblem re-solves now capture solved numeric outputs back into `ProblemInstance` local-state value stores
- Benders-side operational extraction and local slack/dual collection now prefer those cached local-state values when present
- the Benders solver path now retains planning `ProblemInstance`s and captures the returned planning solution onto local-state value stores without requiring eager write-back onto legacy component fields
- `solve_case(..., ::Benders)` no longer depends exclusively on the old recursive `update_with_planning_solution!` walk to push planning results back onto the case
- `BendersResults` now carries planning instances, and the Benders writer can use planning-period `StaticSystem`s directly for capacity and total-cost outputs
- the Benders writer now also uses planning-period `StaticSystem`s for detailed fixed-cost reconstruction, reducing another write-path dependency on mutated period `System`s
- Benders time-weight, direct dual/slack, and Benders full-timeseries metadata paths now also accept planning-period `StaticSystem`s

## Compatibility Strategy

We should preserve compatibility in layers:

- preserve public `run_case`, `generate_model`, and `solve_case` behavior first
- preserve current monolithic outputs while internal build paths change
- use temporary adapters where `MacroEnergySolvers` still expects legacy subproblem dictionaries
- delay removal of field-backed component solve state until the new path is working end to end

## Testing Strategy

Recommended testing by stage:

- Stage 1: `test/test_problem_architecture.jl`
- Stage 2: existing monolithic workflow and output tests in `test/test_workflow.jl`, `test/test_output.jl`, and `test/test_duals.jl`
- Stage 3: add a temporal Benders builder test that checks subproblem spec generation and problem creation
- Stage 4: add a persistence test proving the same subproblem model object is reused across updates
- Stage 5: extend Benders output tests to run on `ProblemInstance`-backed subproblems

Primary example case for early regression:

- `test/test_small_case`

## Current Status

What is already done on this branch:

- planning note updated to use `StaticSystem` and `ReassemblyMap`
- first `src/model/problems/` scaffolding added
- monolithic `generate_model` now routes through a `ProblemInstance`-based builder
- Myopic now reuses the same problem-layer builder path as monolithic
- temporal Benders planning and subproblem construction now route through `ProblemInstance`
- persistent temporal subproblem models are updated and re-solved in place through `UpdateMap`
- active Benders subproblem dicts no longer carry `:system_local`
- Benders output reconstruction now prefers `ProblemInstance` local state plus `ReassemblyMap`
- focused architecture and Benders output utility tests cover the new planning/subproblem seams and are passing

Immediate next task:

- continue shrinking the remaining dependence on component-owned solve state and copied subproblem systems
- keep moving Benders-side postprocessing and any remaining legacy materialization shims onto `ProblemInstance` local state

## Open Questions To Revisit Later

- whether `StaticSystem` should eventually replace the current `System` name
- whether local state should be keyed by integer indices or symbols long term
- whether `ReassemblyMap` should live directly on `ProblemInstance` or be returned by builders separately
- how much of the current field-backed component API should remain public once local state is the primary solve-state location
