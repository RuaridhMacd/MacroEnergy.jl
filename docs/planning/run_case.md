# Run Case Workflow

These flow charts are grounded in the current implementations in:

- `src/utilities/run_tools.jl`
- `src/load_inputs/load_stages_data.jl`
- `src/model/case.jl`
- `src/config/case_settings.jl`
- `src/load_inputs/generate_system.jl`
- `src/model/solver.jl`
- `src/model/generate_model.jl`
- `src/model/myopic.jl`
- `src/model/benders/planning.jl`
- `src/model/problems/build.jl`

## Notes

- `run_case` wraps the main work in `try/catch/finally`, and also registers `atexit(case_cleanup)`.
- `_run_case_impl` does not have a `!` in the current code.
- `create_optimizer` is used for `Monolithic` and `Myopic`.
- `create_optimizer_benders` is used for `Benders`.
- output writing is skipped for `Myopic` in `_run_case_impl`, because Myopic writes during iteration.
- distributed workers are only started and removed for distributed Benders runs.
- `ProblemInstance` creation happens below `solve_case`, not during `load_case`.
- the public APIs still look `Case`/`System`-based, but model construction now largely routes through `StaticSystem` + `ProblemSpec` + `ProblemInstance`.

---
## `run_case`
---

```mermaid
flowchart TD
    A[run_case] --> B[atexit case_cleanup]
    B --> C[set_logger]
    C --> D{try}

    D --> E[setup_user_additions]
    E --> F[load_user_additions]
    F --> G[refresh_user_type_registries!]
    G --> H[Base.invokelatest _run_case_impl]

    H --> I[finally case_cleanup]
    D --> J[catch rethrow]
    J --> I

    click H "#_run_case_impl" "Jump to _run_case_impl"
```

---
<a id="_run_case_impl"></a>
## `_run_case_impl`
---

```mermaid
flowchart TD
    A[_run_case_impl] --> B[load_case]
    B --> C{solution_algorithm case}

    C -- Monolithic or Myopic --> D[create_optimizer]
    C -- Benders --> E[create_optimizer_benders]
    C -- Other --> Z[error]

    D --> F{Benders and Distributed}
    E --> F

    F -- Yes --> G[start_distributed_processes!]
    F -- No --> H[solve_case]
    G --> H

    H --> I[postprocess!]
    I --> J{Myopic}
    J -- Yes --> M
    J -- No --> K[create_output_path]
    K --> L[write_outputs]
    L --> M{Benders and Distributed and nprocs > 1}
    M -- Yes --> N[rmprocs workers]
    M -- No --> O[return case.systems and solution]
    N --> O

    click B "#load_case" "Jump to load_case"
```

---
<a id="solve_case"></a>
## `solve_case`
---

```mermaid
flowchart TD
    A[solve_case] --> B{solution algorithm}

    B -- Monolithic --> C[generate_model]
    B -- Myopic --> D[run_myopic_iteration!]
    B -- Benders --> E[build_temporal_subproblem_bundles]

    E --> F[initialize_planning_problem!]
    F --> G[MacroEnergySolvers.benders]
    G --> H[capture_planning_solution!]
    H --> I[materialize_planning_solution!]
    I --> J[update_with_subproblem_solutions!]

    click C "#probleminstances-monolithic" "Jump to monolithic ProblemInstance creation"
    click D "#probleminstances-myopic" "Jump to Myopic ProblemInstance creation"
    click E "#probleminstances-benders" "Jump to Benders ProblemInstance creation"
    click F "#probleminstances-benders" "Jump to Benders planning ProblemInstances"
```

---
<a id="load_case"></a>
## `load_case`
---

```mermaid
flowchart TD
    A[load_case] --> B{path is dir}
    B -- Yes --> C[path = joinpath path system_data.json]
    B -- No --> D{isjson path}
    C --> D

    D -- No --> E[ArgumentError]
    D -- Yes --> F[load_case_data]
    F --> G[generate_case]
    G --> H[return Case]

    click F "#load_case_data" "Jump to load_case_data"
    click G "#generate_case" "Jump to generate_case"
```

---
<a id="load_case_data"></a>
## `load_case_data`
---

```mermaid
flowchart TD
    A[load_case_data] --> B[load_system_data]
    B --> C{data has key case}
    C -- No --> D[wrap single system into case vector and default settings]
    C -- Yes --> E[keep loaded case data]
    D --> F[return Dict]
    E --> F

    click B "#load_system_data" "Jump to load_system_data"
```

---
<a id="generate_case"></a>
## `generate_case`
---

```mermaid
flowchart TD
    A[generate_case] --> B[configure_case]
    B --> C[read systems_data case]
    C --> D{num systems equals length PeriodLengths}
    D -- No --> E[error]
    D -- Yes --> F[map each period data to empty_system plus generate_system!]
    F --> G[prepare_case!]
    G --> H[return Case]

    click B "#configure_case" "Jump to configure_case"
    click F "#generate_system" "Jump to generate_system!"
    click G "#prepare_case" "Jump to prepare_case!"
```

---
<a id="configure_case"></a>
## `configure_case`
---

```mermaid
flowchart TD
    A[configure_case] --> B{input has path}
    B -- Yes --> C[resolve path and read case settings file]
    B -- No --> D[use provided settings dict]

    C --> E{SolutionAlgorithm is Benders}
    D --> F{SolutionAlgorithm is Benders and BendersSettings missing}

    E -- Yes --> G[load_benders_settings]
    E -- No --> H[configure_case dict]
    F -- Yes --> I[try_load_benders_settings]
    F -- No --> H

    G --> H
    I --> H

    H --> J[merge with defaults]
    J --> K[set_period_lengths!]
    K --> L[set_solution_algorithm!]
    L --> M{Benders}
    M -- Yes --> N[configure_benders!]
    M -- No --> O{Myopic}
    N --> O
    O -- Yes --> P[configure_myopic!]
    O -- No --> Q[validate_case_settings]
    P --> Q
    Q --> R[return NamedTuple settings]
```

---
<a id="generate_system"></a>
## `generate_system!`
---

```mermaid
flowchart TD
    A[generate_system!] --> B[configure_settings]
    B --> C[load_commodities]
    C --> D[load_locations!]
    D --> E[load_time_data]
    E --> F[load! nodes]
    F --> G[load! assets]
    G --> H[return system]
```

---
<a id="prepare_case"></a>
## `prepare_case!`
---

```mermaid
flowchart TD
    A[prepare_case!] --> B[for each system]
    B --> C[compute_annualized_costs!]
    C --> D[discount_fixed_costs!]
    D --> E[compute_retirement_period!]
    E --> F{first system}
    F -- Yes --> G[initialize_min_retired_capacity_track!]
    F -- No --> H[track_min_retired_capacity!]
    G --> I[next system]
    H --> I
```

---
## ProblemInstances
---

This section traces where `ProblemInstance`s are actually created in the current refactor.

- `load_case` and `generate_case` still produce a `Case` containing legacy `System`s.
- `ProblemInstance` creation begins only when we start building optimization problems.
- the common pattern is:
  `System -> StaticSystem -> ProblemSpec -> ProblemInstance -> populate_*_problem!`

```mermaid
flowchart TD
    A[System] --> B[StaticSystem system]
    B --> C[problem_spec or nothing]
    C --> D[build_problem_instance]
    D --> E[initialize_local_state!]
    E --> F[initialize_reassembly_map!]
    F --> G[populate_planning_problem or populate_problem_model or generate_operation_subproblem]

    click D "#build_problem_instance" "Jump to build_problem_instance"
```

---
<a id="probleminstances-monolithic"></a>
## ProblemInstances For Monolithic
---

```mermaid
flowchart TD
    A[solve_case Monolithic] --> B[generate_model]
    B --> C[build_monolithic_problem_instances]
    C --> D[for each system build_problem_instance StaticSystem system nothing]
    D --> E[create_problem_model]
    E --> F[populate_problem_model!]
    F --> G[return one JuMP model]

    click C "#build_monolithic_problem_instances" "Jump to build_monolithic_problem_instances"
    click D "#build_problem_instance" "Jump to build_problem_instance"
```

Monolithic uses the default/full problem spec internally:

- `spec = nothing`
- interpreted as all components, all times, no decomposition boundary

---
<a id="probleminstances-myopic"></a>
## ProblemInstances For Myopic
---

```mermaid
flowchart TD
    A[solve_case Myopic] --> B[run_myopic_iteration!]
    B --> C[loop over periods]
    C --> D[build_problem_instance system nothing]
    D --> E[create_problem_model instance optimizer]
    E --> F[populate_problem_model!]
    F --> G[solve and write outputs]
    G --> H[carry_over_capacities! next period]

    click D "#build_problem_instance" "Jump to build_problem_instance"
```

Myopic currently creates one fresh `ProblemInstance` per period iteration.

---
<a id="probleminstances-benders"></a>
## ProblemInstances For Benders
---

```mermaid
flowchart TD
    A[solve_case Benders] --> B[build_temporal_subproblem_bundles]
    A --> C[initialize_planning_problem!]

    B --> D[build temporal subproblem ProblemInstances]
    C --> E[build_planning_problem]
    E --> F[build planning ProblemInstances]

    D --> G[initialize_subproblems!]
    F --> H[planning_problem model]
    G --> I[MacroEnergySolvers.benders]
    H --> I

    click B "#build_temporal_subproblem_bundles" "Jump to build_temporal_subproblem_bundles"
    click E "#build_planning_problem" "Jump to build_planning_problem"
```

Benders currently creates two families of `ProblemInstance`s:

- planning-period instances:
  one per period, used to build the master/planning problem
- temporal subproblem instances:
  one per temporal subproblem, used to build persistent operational subproblems

After the Benders loop:

- planning solution values are captured onto planning `ProblemInstance`s
- final subproblem solves capture operational values onto subproblem `ProblemInstance`s
- output writing increasingly reads from those instances and their `StaticSystem` / local state

---
<a id="build_problem_instance"></a>
## `build_problem_instance`
---

```mermaid
flowchart TD
    A[build_problem_instance] --> B[ProblemInstance static_system spec]
    B --> C[initialize_local_state!]
    C --> D[initialize_reassembly_map!]
    D --> E[return ProblemInstance]
```

`build_problem_instance` does not populate a JuMP model by itself.

It creates the persistent container that owns:

- `static_system`
- `spec`
- `model`
- local state dictionaries like `node_state` and `edge_state`
- `update_map`
- `reassembly_map`

---
<a id="build_monolithic_problem_instances"></a>
## `build_monolithic_problem_instances`
---

```mermaid
flowchart TD
    A[build_monolithic_problem_instances] --> B[map case.systems]
    B --> C[StaticSystem system]
    C --> D[build_problem_instance static_system nothing]
    D --> E[return Vector ProblemInstance]
```

---
<a id="build_planning_problem"></a>
## `build_planning_problem`
---

```mermaid
flowchart TD
    A[build_planning_problem] --> B[build_planning_problem_instances]
    B --> C[create_named_problem_model first instance]
    C --> D[loop over planning instances]
    D --> E[populate_planning_problem!]
    E --> F[carry_over_capacities! next planning instance]
    F --> G[assemble planning objective expressions]
    G --> H[return model and planning_instances]

    click B "#build_planning_problem_instances" "Jump to build_planning_problem_instances"
```

---
<a id="build_planning_problem_instances"></a>
## `build_planning_problem_instances`
---

```mermaid
flowchart TD
    A[build_planning_problem_instances] --> B[map case.systems]
    B --> C[StaticSystem system]
    C --> D[problem_spec role planning]
    D --> E[build_problem_instance static_system spec]
    E --> F[return Vector planning ProblemInstance]
```

---
<a id="build_temporal_subproblem_bundles"></a>
## `build_temporal_subproblem_bundles`
---

```mermaid
flowchart TD
    A[build_temporal_subproblem_bundles] --> B[loop over case.systems]
    B --> C[loop over subperiod positions]
    C --> D[build_temporal_subproblem_system]
    D --> E[problem_spec role temporal_subproblem time_indices metadata]
    E --> F[build_problem_instance static_system spec]
    F --> G[return bundle instance period_index subproblem_index subperiod_index]

    click F "#build_problem_instance" "Jump to build_problem_instance"
```

This is the current place where temporal Benders subproblem instances are created.

Each returned bundle holds:

- `instance`
- `period_index`
- `subproblem_index`
- `subperiod_index`

The active Benders flow then converts those bundles into persistent subproblem models.

---
<a id="load_system_data"></a>
## `load_system_data`
---

```mermaid
flowchart TD
    A[load_system_data] --> B[resolve absolute path]
    B --> C[prep_system_data]
    C --> D[load_inputs]
    D --> E[return Dict]
```
