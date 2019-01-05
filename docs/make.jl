using Documenter, Plasmo, JuMP, MathProgBase, LightGraphs, Metis

makedocs(sitename="Plasmo.jl - Platform for Scalable Modeling and Optimization", modules=[Plasmo],
        doctest=true,html_prettyurls = get(ENV, "CI", nothing) == "true",
        authors = "Jordan Jalving",
        pages = [
        "Introduction" => "index.md",
        "Quick Start" => "documentation/quickstart.md",
        "ModelGraph" => "documentation/modelgraph.md",
        "Graph Analysis" => "documentation/graphanalysis.md",
        "Solvers" => "documentation/solvers/solvers.md",
        "Tutorials" => "tutorials/tutorials.md",
        "Low-Level Functions" => "low_level/baseplasmograph.md"]
        )

deploydocs(
    repo = "github.com/jalving/Plasmo.jl.git"
    )
