using Documenter, Plasmo, JuMP, LightGraphs

makedocs(sitename="Plasmo.jl - Platform for Scalable Modeling and Optimization", modules=[Plasmo],
        doctest=true,html_prettyurls = get(ENV, "CI", nothing) == "true",
        authors = "Jordan Jalving",
        pages = [
        "Introduction" => "index.md",
        "Quick Start" => "documentation/quickstart.md",
        "Modeling" => "documentation/modelgraph.md",
        "Partitioning" => "documentation/partitioning.md",
        "Manipulation" => "documentation/manipulation.md",
        "Plotting" => "documentation/plotting.md",
        "Solvers" => "documentation/solvers.md",
        "Tutorials" => "tutorials/tutorials.md"]
        )

deploydocs(
    repo = "github.com/jalving/Plasmo.jl.git"
    )
