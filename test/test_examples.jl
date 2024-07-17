#  Copyright 2021, Jordan Jalving, Yankai Cao, Victor Zavala, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at https://mozilla.org/MPL/2.0/.

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
