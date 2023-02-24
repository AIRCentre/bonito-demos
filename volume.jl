volume_app = App(title="Volume") do session::Session
    algorithms = ["mip", "iso", "absorption"]
    algorithm = Observable(first(algorithms))
    algorithm_drop = D.Dropdown("Algorithm", algorithms)
    algorithm = algorithm_drop.value
    N = 100
    data_slider = D.Slider("data param", LinRange(1.0f0, 10.0f0, 100))
    iso_value = D.Slider("iso value", LinRange(0.0f0, 1.0f0, 100))
    slice_idx = D.Slider("slice", 1:N)

    signal = Observable{Array{Float32, 3}}(zeros(Float32, N, N, N))
    on_latest(session, data_slider.value; update=true) do α
        a = -1; b = 2; r = LinRange(-2, 2, N)
        z = ((x, y) -> x + y).(r, r') ./ 5
        me = [z .* sin.(α .* (atan.(y ./ x) .+ z .^ 2 .+ pi .* (x .> 0))) for x = r, y = r, z = r]
        signal[] = me .* (me .> z .* 0.25)
    end

    slice = Observable{Matrix{Float32}}(zeros(Float32, N, N))
    onany_latest(session, signal, slice_idx.value) do x, idx
        slice[] = view(x, :, idx, :)
    end

    fig = Figure()
    cmap = D.Dropdown("Colormap", ["Hiroshige", "Spectral_11", "diverging_bkr_55_10_c35_n256",
        "diverging_cwm_80_100_c22_n256", "diverging_gkr_60_10_c40_n256",
        "diverging_linear_bjr_30_55_c53_n256",
        "diverging_protanopic_deuteranopic_bwy_60_95_c32_n256"])

    vol = volume(fig[1, 1], signal;
        algorithm=map(Symbol, algorithm),
        colormap=cmap.value,
        isovalue=iso_value.value,
        colorrange=(-0.2, 2))

    heat = heatmap(fig[1, 2], slice, colormap=cmap.value, colorrange=(-0.2, 2))

    return D.FlexRow(
        D.Card(D.FlexCol(
            data_slider,
            iso_value,
            slice_idx,
            algorithm_drop,
            cmap,
        )),
        D.Card(fig)
    )
end
