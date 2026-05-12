function start_distributed_processes!(number_of_processes::Int64,case_path::AbstractString)

    # rmprocs.(workers())

    if haskey(ENV,"SLURM_NTASKS")
        parse(Int, ENV["SLURM_NTASKS"]) > number_of_processes ? @warn("SLURM_NTASKS is greater than the number of processes specified. Only $number_of_processes processes will be used.") : nothing
        cpus_per_task = parse(Int, ENV["SLURM_CPUS_PER_TASK"]);
        addprocs(SlurmClusterManager.SlurmManager(); exeflags=["-t $cpus_per_task"])
    else
        ntasks = min(number_of_processes,Sys.CPU_THREADS)
        cpus_per_task = 1;
        addprocs(ntasks)
    end

    project = Pkg.project().path

    @sync for p in workers()
        @async create_worker_process(p,project,case_path) # add a check
    end

    @info("Number of procs: $(nprocs())")
    @info("Number of workers: $(nworkers())")
end

function solver_available(solver_name::Symbol)::Bool
    return isdefined(Main, solver_name)
end

function create_worker_process(pid,project,case_path::AbstractString)

    Distributed.remotecall_eval(Main, pid,:(using Pkg))

    Distributed.remotecall_eval(Main, pid,:(Pkg.activate($(project))))

    Distributed.remotecall_eval(Main, pid, :(using MacroEnergy))

    optional_solvers = [:Gurobi,]
    for solver in optional_solvers
        if solver_available(solver)
            Distributed.remotecall_eval(Main, pid, :(using $solver))
            @debug("Loaded $solver on worker $pid")
        end
    end

    Distributed.remotecall_eval(Main, pid, :(using MacroEnergySolvers))

    Distributed.remotecall_eval(MacroEnergy, pid, :(MacroEnergy.load_user_additions($case_path)))

end
