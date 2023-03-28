using HTTP, Profile

global snapshot = 1
function take_snapshot()
    global snapshot
    for i in 1:10
        GC.gc(true)
    end
    Profile.take_heap_snapshot("snapshot$(snapshot).heapsnapshot")
    snapshot += 1
end

function server_request(request::HTTP.Request)
    try
        if request.target == "/"
            return HTTP.Response("Hello")
        else
            take_snapshot()
            return HTTP.Response("took snapshot")
        end
    catch e
        return HTTP.Response(400, "Error: $e")
    end
end

HTTP.serve(server_request, "0.0.0.0", 8081)
