using Documenter, Plasmo, JuMP, LightGraphs, PlasmoPlots, Suppressor

DocMeta.setdocmeta!(Plasmo, :DocTestSetup, :(using Plasmo); recursive=true)
DocMeta.setdocmeta!(PlasmoPlots, :DocTestSetup, :(using PlasmoPlots); recursive=true)

#Fix issue with GKS for plotting
ENV["GKSwstype"] = "100"

makedocs(sitename="Plasmo.jl", modules=[Plasmo, PlasmoPlots],
        doctest=true, format=Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true"),
        authors = "Jordan Jalving",
        pages = [
        "Introduction" => "index.md",
        "Quickstart" => "documentation/quickstart.md",
        "Modeling with OptiGraphs" => "documentation/modeling.md",
        "Partitioning and Graph Analysis" => "documentation/partitioning.md",
        "Solvers" => "documentation/solvers.md",
        "Tutorials" => [
            "Optimal Control of a Natural Gas Network" => "tutorials/gas_pipeline.md",
            ],
        "API Documentation" => "documentation/api_docs.md"]
        )

deploydocs(
    repo = "github.com/zavalab/Plasmo.jl.git"
    )
