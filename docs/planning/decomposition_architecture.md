# Decomposition Architecture Proposal

## Purpose

This document describes a proposed architecture for supporting monolithic solves, temporal Benders decomposition, and future spatial, sectoral, or mixed decompositions in MacroEnergy.

The main goals are:

- Keep the monolithic workflow simple.
- Support decomposition using a single general abstraction.
- Avoid rebuilding subproblem models across Benders iterations.
- Support persistent CPU or GPU batch subproblem solves.
- Separate static system data from solve-time model state without forcing a disruptive full rewrite.

## Design Summary

The proposed conceptual flow is:

```text
StaticSystem -- ProblemSpec --> ProblemInstance
```

Where:

- `StaticSystem` stores static model data.
- `ProblemSpec` declares which problem to build from that data.
- `ProblemInstance` owns a persistent JuMP model plus the local solve-state and update metadata for that problem.

Monolithic solution is just the default case:

- `ProblemSpec = nothing`
- interpreted internally as "all components, all time, no boundaries"

So the same machinery can support:

- monolithic solves
- temporal decomposition
- spatial decomposition
- sectoral decomposition
- mixed time-spatial-sectoral decomposition

## Core Components

## `StaticSystem`

`StaticSystem` is the static representation of the modeled system.

It should contain:

- typed component stores such as `Node[]`, `Edge[]`, `Transformation[]`, `Storage[]`
- time data
- commodities
- settings needed to interpret the network
- asset membership as lightweight views over component indices
- location membership

`StaticSystem` should **not** own live JuMP variables, expressions, or constraint references.

It is the reusable input to any problem build.

## `ProblemSpec`

`ProblemSpec` is a declarative description of which problem to build from `StaticSystem`.

Typical fields may include:

- included node indices
- included edge indices
- included transformation indices
- included storage indices
- included time slices or subperiods
- boundary and interface definitions
- decomposition role, if relevant

Examples:

- monolithic: all components, all time, no interfaces
- temporal subproblem: all structural components, one time slice
- spatial subproblem: only components in one region plus interface definitions
- sectoral subproblem: only components in one sector plus interface definitions

`ProblemSpec` is a problem description, not solve-state.

It should be expressive enough to describe:

- which components and time indices are included
- which boundaries or interfaces are present
- how those interfaces should be interpreted during build

So boundary/interface metadata should live inside `ProblemSpec`, rather than as a separate top-level architectural object.

## `ProblemInstance`

`ProblemInstance` is the persistent built form of one problem.

Conceptually:

```julia
mutable struct ProblemInstance
    id::ProblemId
    spec::ProblemSpec
    model::Model
    edge_state::Dict{Symbol,EdgeLocalState}
    node_state::Dict{Symbol,NodeLocalState}
    transformation_state::Dict{Symbol,TransformationLocalState}
    storage_state::Dict{Symbol,StorageLocalState}
    update_map::UpdateMap
end
```

This is the object that Benders or a GPU batch solver would repeatedly update and solve.

Important point:

- `ProblemInstance` is **per problem**
- local state is **per component per problem**

If a single global edge appears in the upper problem and in two subproblems, then there are three local states for that edge, one in each `ProblemInstance`.

## Local Solve-State Types

To avoid turning MacroEnergy upside down immediately, a practical transitional approach is to define solve-state structs corresponding to the existing component types, but keep them owned by each `ProblemInstance`.

Examples:

- `EdgeLocalState`
- `NodeLocalState`
- `TransformationLocalState`
- `StorageLocalState`

These local state structs may contain:

- variable refs
- constraint refs
- expression refs
- solution values
- local time ownership metadata

For example, an `EdgeLocalState` may include:

- capacity variable in the upper problem
- flow variables in one subproblem
- budget or interface variables if relevant
- local constraints created for that problem

This lets the implementation remain component-oriented while avoiding a single shared global object carrying solve-state for many problems at once.

## `UpdateMap`

`UpdateMap` stores the metadata needed to update a persistent `ProblemInstance` in place between solves.

Typical use cases:

- fix or bound linking variables from the upper problem
- update right-hand sides of interface constraints
- update variable bounds
- update selected objective coefficients if needed

For Benders and GPU workflows, the design objective is:

- build subproblems once
- keep their matrix structure fixed
- only apply cheap in-place updates between iterations

So `UpdateMap` should support:

- locating model objects to update
- applying updates without rebuilding the model

`UpdateMap` is not the problem description. It is the map used to patch a built problem efficiently.

## `ReassemblyMap`

In addition to `UpdateMap`, the architecture likely needs a cross-problem `ReassemblyMap`.

This supports operations like:

- reconstructing global `flow` results on an `Edge`
- reconstructing node prices or balance results
- tracking which problem owns which portion of a component

Conceptually, this map answers questions like:

- which problems contain this edge?
- which time indices does each problem own for this edge?
- where should local solution values be written in the global result vector?

This is especially important for decomposed solves.

Unlike `ProblemSpec`, `ReassemblyMap` is not the declarative description of the problem.
It is derived build metadata used to reconstruct global outputs from local per-problem state.

## Workflow

## Monolithic Solve

Monolithic solve is the simplest case.

### Inputs

- one `StaticSystem`
- `ProblemSpec = nothing` or equivalent full-problem spec

### Build

1. Normalize `spec = nothing` into the full problem.
2. Build one `ProblemInstance`.
3. Create local state for all participating components.
4. Build one JuMP model.

### Solve

1. Solve the JuMP model once.
2. Write results back through the assembly logic, which is trivial in the monolithic case.

### Notes

- No decomposition-specific machinery is required.
- This provides a clean baseline for correctness.

## Temporal Benders Decomposition

Temporal decomposition should be the first decomposition target because it is simpler than spatial or sectoral decomposition.

### Inputs

- one shared `StaticSystem`
- one upper problem spec
- one `ProblemSpec` per temporal subproblem

### Build

1. Build the planning `ProblemInstance`.
2. Build one persistent subproblem `ProblemInstance` per temporal slice.
3. Each temporal subproblem usually includes:
   - all structural components
   - only a subset of time indices
4. Build `UpdateMap`s so each subproblem can receive planning values via cheap updates.

### Benders Iteration

1. Solve the planning problem.
2. Update each subproblem in place.
   - usually by changing bounds or right-hand sides
3. Solve all subproblems.
4. Collect duals and costs.
5. Add cuts to the upper problem.
6. Repeat.

### Notes

- Subproblem models should persist across iterations.
- The goal is to avoid rebuilding the JuMP models.
- This fits well with CPU parallelism and GPU batch LP solves.

## Spatial or Sectoral Decomposition

Spatial and sectoral decomposition use the same architecture, but the `ProblemSpec`s become more expressive.

### Inputs

- one shared `StaticSystem`
- one upper problem spec
- one `ProblemSpec` per spatial/sectoral subproblem

### Build

1. Select the subset of components owned by each problem.
2. Include all required dependencies.
3. Define interfaces where edges, balances, or capacities cross decomposition boundaries.
4. Build one persistent `ProblemInstance` per problem.

### Benders Iteration

1. Solve the upper problem.
2. Update interface values or linking values in each subproblem using `UpdateMap`.
3. Solve subproblems.
4. Aggregate costs, duals, and cuts.
5. Update the upper problem.

### Notes

- This is more general than temporal decomposition.
- The architecture should avoid hard-coding decomposition logic in the solver.
- Instead, decomposition builders should produce `ProblemSpec`s and interface/update metadata.

## GPU Batch Solve

The architecture should support a solver path where many small LP subproblems are solved in batch on a GPU.

The common intended workflow is:

1. Build many persistent subproblem `ProblemInstance`s on a single CPU node.
2. Hand their `Vector{Model}` to the GPU batch LP solver.
3. Between iterations, update each subproblem in place.
4. Re-solve the batch without rebuilding models.

This strongly motivates:

- persistent `ProblemInstance`s
- fixed model structure across Benders iterations
- updates restricted to bounds, right-hand sides, and similarly cheap parameter changes

Distributed workers may still help with:

- partitioning
- `ProblemSpec` generation
- preprocessing

But the common GPU path should assume that the batch of JuMP models is owned by one host process.

## Recommended Migration Strategy

To minimize disruption, implementation should proceed in stages.

### Stage 1: Introduce the abstractions

- define `StaticSystem`
- define `ProblemSpec`
- define `ProblemInstance`
- define local solve-state structs
- define `UpdateMap`

### Stage 2: Keep existing workflows working

- make monolithic solve use the new builder
- preserve current external APIs as much as possible

### Stage 3: Migrate temporal Benders

- replace ad hoc subproblem dicts with persistent `ProblemInstance`s
- preserve current Benders behavior while switching to explicit update maps

### Stage 4: Add result reassembly maps

- support reconstruction of global component results from decomposed solves

### Stage 5: Add spatial/sectoral decomposition builders

- build these on top of `ProblemSpec`
- avoid embedding decomposition-specific graph surgery inside the core solver logic

### Stage 6: Add GPU batch solver integration

- solve many persistent subproblems on one CPU host with one GPU call path

## Benefits

This architecture provides:

- one unified description for monolithic and decomposed models
- cleaner separation between input data and solve-time state
- persistent subproblem models suitable for Benders
- a natural path to GPU batch LP solves
- a consistent foundation for temporal, spatial, sectoral, and mixed decomposition

## Open Design Choices

The following points still need to be decided during implementation:

- the exact contents of `StaticSystem`
- whether local state should be keyed by symbols or global component indices
- the exact boundary/interface representation in `ProblemSpec`
- whether `ReassemblyMap` should live directly on `ProblemInstance` or be managed alongside it
- how much compatibility with the existing object layout should be preserved during transition

## Proposed Direction

The recommended direction is:

- start with monolithic and temporal Benders
- preserve current high-level workflows
- introduce `ProblemSpec`, `ProblemInstance`, and `UpdateMap`
- keep subproblem models persistent
- only then extend the same architecture to spatial, sectoral, and mixed decomposition
