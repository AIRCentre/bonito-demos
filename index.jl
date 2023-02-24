function find_route(server, target_app)
    for (route, app) in server.routes.table
        app === target_app && return route
    end
    return nothing
end

function link_app(server, app, title=app.title)
    route = find_route(server, app)
    url = online_url(server, route)
    imgname = replace(lowercase(title), " " => "_")
    img_asset = Asset(joinpath(@__DIR__, "$(imgname).png"))
    return DOM.a(DOM.img(src=img_asset, height="200px", style="height: 200px"), href=url)
end

function app_card(app)
    return D.Card(
        D.FlexCol(
            DOM.h2(app.title),
            link_app(server, app)
        )
    )
end

index_app = App() do
    cards = app_card.([volume_app, signal_filtering_app, diagnostic_app])
    return DOM.div(
        DOM.h1("Bonito Demos:"),
        D.FlexRow(cards...)
    )
end
