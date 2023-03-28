# Needed to run with `sudo julia` which changes the homedir
# sudo is needed for a process to listen to port `80`
# DEPOT_PATH[1] = "/home/sdanisch/.julia/"
using JSServe
ENV["JULIA_DEBUG"] = JSServe

using WGLMakie, ColorSchemes
using Markdown
using JSServe: Dropdown, Asset
import JSServe.TailwindDashboard as D
using Observables
using SignalAnalysis
using DSP
using FFTW
using Random
using Sockets

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

function NaviButton(title)
    class = "focus:outline-none focus:shadow-outline focus:border-blue-300 bg-white bg-gray-100 hover:bg-white text-gray-800 font-semibold m-1 p-1 border border-gray-400 rounded shadow"
    ref = "/" * lowercase(replace(replace(title, "Home" => ""), " "=> "_"))
    return DOM.a(title, href=ref, class=class)
end

function Site(content, title, footer)
    navigation = D.Card(D.FlexRow(
        NaviButton.(["Home", "Clima", "Volume", "Signal Filtering", "Diagnostic"])...;
        ); class="inset-x-0 top-0")
    footer_div = DOM.footer(footer; class="text-center w-full bg-gray-100 p-2 inset-x-0 bottom-0 absolute")
    return D.FlexCol(navigation, content, footer_div)
end

isdefined(Main, :server) && close(server)

server = Server("0.0.0.0", 8081; proxy_url="http://simi-homy.ddns.net:8081")

include("diagnostic.jl")
route!(server, "/diagnostic" => diagnostic_app);
include("volume.jl")
route!(server, "/volume" => volume_app)
include("signal_filtering.jl")
route!(server, "/signal_filtering" => signal_filtering_app);
include("clima.jl")
route!(server, "/clima" => clima_app);
include("index.jl")
route!(server, "/" => index_app);

# \\sshfs\server@simi-homy.ddns.net
8.87
