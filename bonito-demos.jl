# Needed to run with `sudo julia` which changes the homedir
# sudo is needed for a process to listen to port `80`
DEPOT_PATH[1] = "/home/sdanisch/.julia/"

using WGLMakie, ColorSchemes
using JSServe, Markdown
using JSServe: Dropdown, Asset
import JSServe.TailwindDashboard as D
using Observables
using SignalAnalysis
using DSP
using FFTW
using Random

function on_latest(f, session, observable::Observable{T}; update=false) where T
    queue = Channel{T}(64) do channel
        while isopen(channel)
            value = take!(channel)
            if isempty(channel)
                f(value)
            end
        end
    end
    on(session, observable; update=update) do new_value
        put!(queue, new_value)
    end
end

function onany_latest(f, session, args...)
    callback = Observables.OnAny(f, args)
    obsfuncs = ObserverFunction[]
    for observable in args
        if observable isa AbstractObservable
            obsfunc = on_latest(callback, session, observable)
            push!(obsfuncs, obsfunc)
        end
    end
    return obsfuncs
end

isdefined(Main, :server) && close(server)
server = Server("0.0.0.0", 80; proxy_url="http://bonito.makie.org")

include("diagnostic.jl")
route!(server, "/diagnostic" => diagnostic_app)
include("volume.jl")
route!(server, "/volume" => volume_app)
include("signal_filtering.jl")
route!(server, "/signal_filtering" => signal_filtering_app)

include("index.jl")
route!(server, "/" => index_app)
