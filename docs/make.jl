using Documenter, Plasmo

makedocs(modules=[Plasmo],
        doctest=true)

deploydocs(deps   = Deps.pip("mkdocs", "python-markdown-math"),
    repo = "github.com/jalving/Plasmo.jl.git",
    julia  = "0.6.0",
    osname = "linux")
