using Suppressor

const EXAMPLES = filter(
    ex -> endswith(ex, ".jl") && ex != "run_examples.jl",
    readdir(joinpath(@__DIR__, "../examples")),
)

for example in EXAMPLES
    # skip until we get PlasmoPlots updated
    if example == "06_plotting_optigraphs.jl"
        continue
    else
        @suppress include(joinpath(@__DIR__, "../examples", example))
    end
end
