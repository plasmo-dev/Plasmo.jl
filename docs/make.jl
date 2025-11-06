#  Copyright 2021, Jordan Jalving, Yankai Cao, Victor Zavala, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at https://mozilla.org/MPL/2.0/.

using Documenter, Plasmo, Suppressor, Graphs
# using PlasmoPlots

DocMeta.setdocmeta!(Plasmo, :DocTestSetup, :(using Plasmo); recursive=true)
# DocMeta.setdocmeta!(PlasmoPlots, :DocTestSetup, :(using PlasmoPlots); recursive=true)

#Fix issue with GKS for plotting
ENV["GKSwstype"] = "100"

makedocs(;
    sitename="Plasmo.jl",
    modules=[Plasmo], #, PlasmoPlots],
    doctest=true,
    checkdocs=:export,
    format=Documenter.HTML(; prettyurls=get(ENV, "CI", nothing) == "true"),
    authors="Jordan Jalving",
    pages=[
        "Introduction" => "index.md",
        "Quickstart" => "documentation/quickstart.md",
        "Modeling with OptiGraphs" => "documentation/modeling.md",
        "Graph Processing and Analysis" => "documentation/graph_processing.md",
        "API Documentation" => "documentation/api_docs.md",
        "Distributed Memory" => [
            "Introduction" => "documentation/distributed.md",
            "Quickstart" => "documentation/distributed_quickstart.md"
        ],
        "Tutorials" => [
            "Supply Chain Optimization" => "tutorials/supply_chain.md",
            "Multi-Horizon Model Predictive Control" => "tutorials/MHMPC.md",
            "Optimal Control of a Quadcopter" => "tutorials/quadcopter.md",
            "Hierarchical HVAC Optimization" => "tutorials/HVAC.md",
            "Optimal Control of a Natural Gas Network" => "tutorials/gas_pipeline.md"
        ],
    ],
)

deploydocs(; repo="github.com/plasmo-dev/Plasmo.jl.git")
