
"""
Compute FIR filterorder
"""
function default_fir_filterorder(responsetype::FilterType, samplingrate::Number)
    # filter settings are the same as firfilt eeglab plugin (Andreas Widmann) and MNE Python.
    # filter order is set to 3.3 times the reciprocal of the shortest transition band
    # transition band is set to either
    # min(max(l_freq * 0.25, 2), l_freq)
    # or
    # min(max(h_freq * 0.25, 2.), nyquist - h_freq)
    #
    # That is, 0.25 times the frequency, but maximally 2Hz

    transwidthratio = 0.25 # magic number from firfilt eeglab plugin
    fNyquist = samplingrate ./ 2
    cutOff = responsetype.w * samplingrate
    # what is the maximal filter width we can have
    if typeof(responsetype) <: Highpass
        maxDf = cutOff
        df = minimum([maximum([maxDf * transwidthratio, 2]), maxDf])
    elseif typeof(responsetype) <: Lowpass
        #for lowpass we have to look back from nyquist
        maxDf = fNyquist - cutOff
        df = minimum([maximum([cutOff * transwidthratio, 2]), maxDf])
    end

    filterorder = 3.3 ./ (df ./ samplingrate)
    filterorder = Int(filterorder ÷ 2 * 2) # we need even filter order

    if typeof(responsetype) <: Highpass
        filterorder += 1 # we need odd filter order
    end
    return filterorder
end

sinusoidal_pulse(x, freq) = ((x > 1 && x < 1 + 2π / 1π) ? 1.5sin.(2π * freq .* x) : 0)

function erp(x, freq)
    # ERP
    σ = 0.5
    σ2 = 0.25
    σ3 = 1.5
    g(x, σ) = -1 / σ√2π * ℯ^(-(x - 2)^2 / 2σ^2)
    g2(x, σ2) = 1 / σ2√2π * 0.9ℯ^(-(x - 2)^2 / 2σ2^2)
    g3(x, σ3) = -2 / σ3√2π * 1.5ℯ^(-(x - 5)^2 / 2σ3^2)
    return 5g(2x, σ) + 5g2(2x, σ2) + 5g3(2x, σ3)
end

H(x) = 0.5 * (sign.(x) + 1)

step_function(x, freq) = H(x - 1) - H(x - 2)
# Unit Impulse (Scaled x10)
unit_impulse(x, freq) = 10 * (x == 1)

function filterdelay(fobj::Vector)
    return (length(fobj) - 1) ÷ 2
end

function generate_signal(noise, line_noise, func_idx, f, shift, freq)
    rng = MersenneTwister(func_idx)
    ts = 0.004
    tmax = 7
    t = 0:ts:tmax
    n = length(t)
    # signal
    signal = f.(t, freq) + noise .* randn(rng, size(t)) + line_noise * 0.5cos.(2π * 50 * t) + shift * H.(t .- 2)

    # fourier transformation
    F = fft(signal) |> fftshift
    freqs = fftfreq(length(t), 1 / ts) |> fftshift
    return (; signal, F, freqs)
end

function apply_filter(selection_filter, selection_method, low, high, (; signal, F, freqs))
    ts = 0.004
    tmax = 7
    t = 0:ts:tmax
    n = length(t)
    if low > high && (selection_filter == "Bandpass" || selection_filter == "Bandstop")
        return md"""
        !!! warning \"Wrong slider configuration \"
            Because of some limitations in the implementation, some slider configurations are possible which are not desirable! **Low cutoff must be smaller than high cutoff!**
        """
    end
    if selection_filter == "Lowpass"
        # Lowpass
        responsetype = Lowpass(low; fs=1 / ts)
    elseif selection_filter == "Highpass"
        # Highpass
        responsetype = Highpass(high; fs=1 / ts)
    elseif selection_filter == "Bandpass"
        # Bandpass
        # set responsetype
        if selection_method == "FIR causal" || selection_method == "FIR acausal"
            responsetype_bpass_low = Lowpass(high; fs=1 / ts)
            responsetype_bpass_high = Highpass(low; fs=1 / ts)
        else
            responsetype = Bandpass(low, high, fs=1 / ts)
        end

    elseif selection_filter == "Bandstop"
        # Notch
        # set responsetype (switch high an low cutoff)
        if selection_method == "FIR causal" || selection_method == "FIR acausal"
            responsetype_bpass_low = Lowpass(low; fs=1 / ts)
            responsetype_bpass_high = Highpass(high; fs=1 / ts)
        else
            responsetype = Bandstop(low, high, fs=1 / ts)
        end
    end

    if selection_method == "FIR causal" || selection_method == "FIR acausal"

        # FIR Hamming causal or acausal

        if selection_filter == "Bandpass" || selection_filter == "Bandstop"
            # if bandpass or bandstop

            # compute the filter order for FIR
            order_bpass_low = default_fir_filterorder(responsetype_bpass_low, 1 / ts)
            order_bpass_high = default_fir_filterorder(responsetype_bpass_high, 1 / ts)

            # set designmethod based on filterorder
            designmethod_bpass_low = FIRWindow(hamming(order_bpass_low), scale=true)
            designmethod_bpass_high = FIRWindow(hamming(order_bpass_high), scale=true)

            # compute delay
            if selection_method == "FIR acausal" && (selection_filter == "Bandpass" || selection_filter == "Bandstop")
                delay_bpass_low = filterdelay(digitalfilter(responsetype_bpass_low,
                    designmethod_bpass_low))

                delay_bpass_high = filterdelay(digitalfilter(responsetype_bpass_high,
                    designmethod_bpass_high))

                if selection_filter == "Bandpass"
                    delay = delay_bpass_low + delay_bpass_high
                else
                    delay = 0
                end
            else
                delay_bpass_low = 0
                delay_bpass_high = 0
                delay = 0
            end
        else
            # if lowpass or highpass FIR
            order = default_fir_filterorder(responsetype, 1 / ts)
            designmethod = FIRWindow(hamming(abs.(order)), scale=true)
            if selection_method == "FIR acausal"
                delay = filterdelay(digitalfilter(responsetype, designmethod))
            else
                delay = 0
            end
        end
    elseif selection_method == "Butterworth"
        # Butterworth
        # set designmethod
        designmethod = Butterworth(4)

        # set delay to zero
        delay = 0

    elseif selection_method == "Chebychev1"
        # Chebyshev1
        # set designmethod
        designmethod = Chebyshev1(4, 1)

        # set delay to zero
        delay = 0
    end
    # filter response
    signal_base = zeros(size(t))
    signal_base[end÷2] = 1
    # filtering
    if (selection_method == "FIR causal" || selection_method == "FIR acausal") && selection_filter == "Bandpass"
        # filtering if bandpass
        # apply low and higpasss filter sequentially after each other
        signal_filt_temp = filt(
            digitalfilter(responsetype_bpass_low, designmethod_bpass_low), signal)

        signal_filt = filt(
            digitalfilter(responsetype_bpass_high, designmethod_bpass_high), signal_filt_temp)

        # same for filter response
        signal_base_filt_temp = filt(digitalfilter(responsetype_bpass_low,
                designmethod_bpass_low), signal_base)

        signal_base_filt = filt(digitalfilter(responsetype_bpass_high,
                designmethod_bpass_high), signal_base_filt_temp)

    elseif (selection_method == "FIR causal" || selection_method == "FIR acausal") && selection_filter == "Bandstop"
        # filtering if bandstop

        # apply low and highpass filter each separate to signal and then combine
        sginal_filt_low = filt(digitalfilter(responsetype_bpass_low,
                designmethod_bpass_low), signal)

        sginal_filt_high = filt(digitalfilter(responsetype_bpass_high,
                designmethod_bpass_high), signal)

        sginal_filt_low = circshift(sginal_filt_low, -delay_bpass_low)
        sginal_filt_high = circshift(sginal_filt_high, -delay_bpass_high)

        signal_filt = sginal_filt_low .+ sginal_filt_high


        # same for filter response
        signal_base_filt_low = filt(digitalfilter(responsetype_bpass_low,
                designmethod_bpass_low), signal_base)

        signal_base_filt_high = filt(digitalfilter(responsetype_bpass_high,
                designmethod_bpass_high), signal_base)

        signal_base_filt = signal_base_filt_low .+ signal_base_filt_high

    else
        # if low or highpass
        # filtered signal
        signal_filt = filt(digitalfilter(responsetype, designmethod), signal)

        # filter in time domain
        signal_base_filt = filt(digitalfilter(responsetype, designmethod), signal_base)
    end

    # filter in frequency domain
    F_base_filt = fft(signal_base_filt) |> fftshift
    freqs_base_filt = fftfreq(length(t), 1 / ts) |> fftshift

    # fourier transformation
    F_filt = fft(signal_filt) |> fftshift
    freqs_filt = fftfreq(length(t), 1 / ts) |> fftshift
    return (; t, signal, signal_filt, delay, freqs, freqs_filt, freqs_base_filt, F_filt, F_base_filt, F)
end


function plot1(response)
    points = map(response) do args
        (; t, signal) = args
        return Point2f.(t, signal)
    end
    points2 = map(response) do args
        (; t, signal_filt, delay) = args
        return Point2f.(t, circshift(signal_filt, -delay))
    end
    f = lines(points, color=(:white, 0.3))
    lines!(points2)
    f
end

function plot2(response)
    ts = 0.004
    tmax = 7
    t = 0:ts:tmax
    n = length(t)
    fig = Figure()
    (; freqs_filt, F_filt) = response[]
    max_idx = round(freqs_filt[freqs_filt.>=0][argmax(abs.(F_filt[n÷2+1:n]))], digits=1)
    ax = Axis(fig[1, 1];
        title="Spectrum (filtered)",
        xscale=log10, limits=(1, max_idx, nothing, nothing),
        xticks=[1, 10, 100, max_idx])

    points1 = map(response) do args
        (; freqs, F) = args
        return Point2f.(freqs[freqs.>=0], abs.(F[n÷2+1:n]))
    end

    lines!(ax, points1)

    points2 = map(response) do args
        (; freqs_base_filt, F_base_filt, F) = args
        max = maximum(abs.(F[n÷2+1:n]))
        return Point2f.(freqs_base_filt[freqs_base_filt.>=0], abs.(F_base_filt[n÷2+1:n]) .* max)
    end

    # plot the filter response
    scatter!(ax, points2, color=(:white, 0.5), markersize=10)
    # plot the frequency spectrum of the filtered signal
    points3 = map(response) do args
        (; freqs_filt, F_filt, F) = args
        max = maximum(abs.(F[n÷2+1:n]))
        return Point2f.(freqs_filt[freqs_filt.>=0], abs.(F_filt[n÷2+1:n]))
    end

    lines!(ax, points3)
    fig
end

using Hyperscript
import JSServe.TailwindDashboard as D

write("app.css", """
h2 {
    color: white
}
""")

signal_filtering_app = App(title="Signal Filtering", threaded=true) do session
    selection_function = D.Dropdown("Function", [erp, unit_impulse, step_function, sinusoidal_pulse], index=1)
    selection_filter = D.Dropdown("Filter", ["Lowpass", "Highpass", "Bandpass", "Bandstop"], index=3)
    selection_method = D.Dropdown("Method", ["FIR causal", "FIR acausal","Butterworth", "Chebychev1"], index=2)

    noise = D.Slider("Noise", [0, 0.1, 0.4])
    shift = D.Checkbox("Shift", true)
    freq = D.Slider("Frequency", [1, 2, 4, 8, 16])
    slider_range = [0.5, 1, 3.5, 5, 10, 20, 40, 60]
    slider_cutoff_low = D.Slider("cutoff low", slider_range, value=0.5)
    slider_cutoff_high = D.Slider("cutoff high", slider_range, value=60)
    line_noise = D.Checkbox("Line Noise", true)

    filter_sliders = map(selection_filter.value) do filter
        if filter == "Lowpass"
            return DOM.div(slider_cutoff_low)
        elseif filter == "Highpass"
            return DOM.div(slider_cutoff_high)
        else
            # Slider for bandpass/bandstop
            return DOM.div(slider_cutoff_low, slider_cutoff_high)
        end
    end
    signal_obs = map(generate_signal, noise.value, line_noise.value, selection_function.option_index, selection_function.value, shift.value, freq.value)
    response = map(apply_filter, selection_filter.value, selection_method.value, slider_cutoff_low.value, slider_cutoff_high.value, signal_obs)

    ui = D.Card(D.FlexCol(
        selection_function,
        selection_filter,
        selection_method,
        noise,
        shift,
        freq,
        filter_sliders,
        line_noise
    ))
    plots = with_theme(Makie.theme_dark()) do
        D.FlexCol(plot1(response), plot2(response))
    end
    dom = D.Card(D.FlexRow(ui, D.Card(plots)); style="background-color: #1A1A1A")
    footer = DOM.div("cc-by Luis Lips & Benedikt Ehinger / MIT ", DOM.a("github.com/s-ccs/interactive-pluto-notebooks", href="https://github.com/s-ccs/interactive-pluto-notebooks"))
    return Site(DOM.div(JSServe.Asset("app.css"), dom), "Signal Filtering", footer)
end;
