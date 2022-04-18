using Documenter, Plasmo, JuMP, LightGraphs, PlasmoPlots

#Fix issue with GKS for plotting
ENV["GKSwstype"] = "100"

makedocs(sitename="Plasmo.jl", modules=[Plasmo],
        doctest=true, format=Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true"),
        authors = "Jordan Jalving",
        pages = [
        "Introduction" => "index.md",
        "Quickstart" => "documentation/quickstart.md",
        "Modeling with OptiGraphs" => "documentation/modeling.md",
        "Partitioning and Graph Analysis" => "documentation/partitioning.md",
        "Solvers" => "documentation/solvers.md",
        "Tutorials" => "tutorials/tutorials.md",
        "API Documentation" => "documentation/api_docs.md"]
        )

deploydocs(
    repo = "github.com/zavalab/Plasmo.jl.git"
    )
