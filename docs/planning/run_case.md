# Run Case Workflow

These flow charts are grounded in the current implementations in:

- `src/utilities/run_tools.jl`
- `src/load_inputs/load_stages_data.jl`
- `src/model/case.jl`
- `src/config/case_settings.jl`
- `src/load_inputs/generate_system.jl`

## Notes

- `run_case` wraps the main work in `try/catch/finally`, and also registers `atexit(case_cleanup)`.
- `_run_case_impl` does not have a `!` in the current code.
- `create_optimizer` is used for `Monolithic` and `Myopic`.
- `create_optimizer_benders` is used for `Benders`.
- output writing is skipped for `Myopic` in `_run_case_impl`, because Myopic writes during iteration.
- distributed workers are only started and removed for distributed Benders runs.

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
