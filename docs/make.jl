using Documenter, Plasmo

makedocs(sitename="Plasmo", modules=[Plasmo],
        doctest=true,html_prettyurls = get(ENV, "CI", nothing) == "true",
        authors = "Jordan Jalving",
        pages = [
        "Introduction" => "index.md",
        "Quick Start" => "quick_start/simple_example.md",
        "Documentation" => "documentation/graph_functions.md",
        "Tutorials" => "tutorials/example_1.md"]
        )

# deploydocs(deps   = Deps.pip("mkdocs", "python-markdown-math"),
#     repo = "github.com/jalving/Plasmo.jl.git",
#     julia  = "1.0.3",
#     osname = "linux")
