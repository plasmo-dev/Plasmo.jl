using Documenter, Plasmo, PlasmoPlots, Suppressor

DocMeta.setdocmeta!(Plasmo, :DocTestSetup, :(using Plasmo); recursive=true)
DocMeta.setdocmeta!(PlasmoPlots, :DocTestSetup, :(using PlasmoPlots); recursive=true)

#Fix issue with GKS for plotting
ENV["GKSwstype"] = "100"

makedocs(;
    sitename="Plasmo.jl",
    modules=[Plasmo, PlasmoPlots],
    doctest=false,
    format=Documenter.HTML(; prettyurls=get(ENV, "CI", nothing) == "true"),
    authors="Jordan Jalving",
    pages=[
        "Introduction" => "index.md",
        "Quickstart" => "documentation/quickstart.md",
        "Modeling with OptiGraphs" => "documentation/modeling.md",
        "Graph Partitioning and Processing" => "documentation/partitioning.md",
        "Tutorials" =>
            ["Optimal Control of a Natural Gas Network" => "tutorials/gas_pipeline.md",
            "Optimal Control of a Quadcopter" => "tutorials/quadcopter.md"],
        "API Documentation" => "documentation/api_docs.md",
    ],
)

deploydocs(; repo="github.com/plasmo-dev/Plasmo.jl.git")
