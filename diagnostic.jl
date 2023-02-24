

idle_time(info::Sys.CPUinfo) = Int64(info.cpu_times!idle)

busy_time(info::Sys.CPUinfo) = Int64(
    info.cpu_times!user + info.cpu_times!nice + info.cpu_times!sys + info.cpu_times!irq,
)

"""
    cpu_percent(period)
CPU usage between 0.0 and 100 [percent]
The idea is borrowed from https://discourse.julialang.org/t/get-cpu-usage/24468/7
Thank you @fonsp.
"""
function cpu_percent(period::Real=1.0)
    info = Sys.cpu_info()
    busies = busy_time.(info)
    idles = idle_time.(info)

    sleep(period)

    info = Sys.cpu_info()
    busies = busy_time.(info) .- busies
    idles = idle_time.(info) .- idles
    return 100 * busies ./ (idles .+ busies)
end

function get_cpu_usage!(buffer, last_info, current_info)
    return map!(buffer, last_info, current_info) do last, current
        busies = busy_time(current) - busy_time(last)
        idles = idle_time(current) - idle_time(last)
        return 100 * busies ./ (idles .+ busies)
    end
end

struct CPUWatcher
    value::Observable{Vector{Float32}}
    task::Base.RefValue{Task}
    task_condition::Base.RefValue{Bool}
    sampling_interval_s::Base.RefValue{Float64}
end

function CPUWatcher(sampling_interval_s::Number=1.0)
    info = Sys.cpu_info()
    return CPUWatcher(
        Observable(zeros(Float32, length(info))),
        Base.RefValue{Task}(),
        Base.RefValue(true),
        Base.RefValue{Float64}(sampling_interval_s),
    )
end

function start!(cpu_watcher::CPUWatcher)
    if !isassigned(cpu_watcher.task) || istaskdone(cpu_watcher.task[])
        cpu_watcher.task_condition[] = true
        last_info = Sys.cpu_info()
        tstart = time_ns()
        cpu_watcher.task[] = @async while cpu_watcher.task_condition[]
            telapsed = (time_ns() - tstart) / 10^9
            to_sleep = cpu_watcher.sampling_interval_s[] - telapsed
            to_sleep < 0.004 ? yield() : sleep(to_sleep)
            current_info = Sys.cpu_info()
            tstart = time_ns()
            cpu_usage.value[] = get_cpu_usage!(cpu_usage.value[], last_info, current_info)
            last_info = current_info
        end
    end
end

function stop!(cpu_watcher::CPUWatcher)
    !isassigned(cpu_watcher.task) || istaskdone(cpu_watcher.task[]) && return
    cpu_watcher.task_condition[] = false
    return fetch(cpu_watcher.task[])
end

struct RAMWatcher
    value::Observable{Float32}
    task::Base.RefValue{Task}
    task_condition::Base.RefValue{Bool}
    sampling_interval_s::Base.RefValue{Float64}
end

function RAMWatcher(sampling_interval_s::Number=1.0)
    return RAMWatcher(
        Observable(0.0f0),
        Base.RefValue{Task}(),
        Base.RefValue(true),
        Base.RefValue{Float64}(sampling_interval_s),
    )
end

function start!(watcher::RAMWatcher)
    if !isassigned(watcher.task) || istaskdone(watcher.task[])
        watcher.task_condition[] = true
        tstart = time_ns()
        watcher.task[] = @async while watcher.task_condition[]
            telapsed = (time_ns() - tstart) / 10^9
            to_sleep = watcher.sampling_interval_s[] - telapsed
            to_sleep < 0.004 ? yield() : sleep(to_sleep)
            free_memory = Sys.free_memory() / 10^9
            tstart = time_ns()
            watcher.value[] = free_memory
        end
    end
end

function history(input::Observable{<:AbstractVector}, nhistory=100)
    history = zeros(eltype(input[]), nhistory, length(input[]))
    history_obs = Observable(history)
    on(input) do new_vals
        history[begin, :] .= new_vals
        notify(history_obs)
        history .= circshift(history, (1, 0))
        return
    end
    return history_obs
end

function history(input::Observable{T}, nhistory=100) where {T<:Number}
    history = zeros(T, nhistory)
    history_obs = Observable(history)
    on(input) do new_val
        history[begin] = new_val
        notify(history_obs)
        history .= circshift(history, 1)
        return
    end
    return history_obs
end

cpu_usage = CPUWatcher()
start!(cpu_usage)
cpu_history = history(cpu_usage.value)

ram_usage = RAMWatcher()
start!(ram_usage)
ram_history = history(ram_usage.value)

diagnostic_app = App(title="Diagnostic") do session
    # bind global observable to session lifecycle
    chist = map(identity, session, cpu_history)
    rhist = map(identity, session, ram_history)
    fig, ax, pl = heatmap(chist; axis=(; ylabel="%", title="CPU usage"), colormap=[:green, :yellow, :red], colorrange=(0, 100))
    barplot(fig[2, 1], rhist; axis=(; ylabel="Gb", title="RAM usage", limits=(nothing, nothing, 0, Sys.total_memory()/10^9)))
    return DOM.div(fig)
end
