#  Copyright 2021, Jordan Jalving, Yankai Cao, Victor Zavala, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at https://mozilla.org/MPL/2.0/.

# macro helpers
_get_name(c::Symbol) = c
_get_name(c::Nothing) = ()
_get_name(c::AbstractString) = c
function _get_name(c::Expr)
    if c.head == :string
        return c
    else
        return c.args[1]
    end
end

"""
    @optinode(optigraph, expr...)

Add a new optinode to `optigraph`. The expression `expr` can either be

* of the form `nodename` creating a single optinode with the variable name `varname`
* of the form `nodename[...]` or `[...]` creating a container of optinodes using JuMP Containers

"""
macro optinode(graph, args...)
    #check arguments
    @assert length(args) <= 1
    if isempty(args)
        macro_code = :(add_node($graph))
    else
        #get the name passed into the macro expression
        var = Base.string(_get_name(args[1]))
        macro_code = quote
            container = JuMP.Containers.@container($(args...), add_node($graph))
            if isa(container, Plasmo.OptiNode)
                set_name(container, Symbol($var))
            else
                #set node labels
                axs = axes(container)
                terms = collect(Base.Iterators.product(axs...))[:]
                for (i, node) in enumerate(container)
                    JuMP.set_name(node, Symbol($var * "[$(string(terms[i]...))]"))
                end
            end
            $(graph).obj_dict[Symbol($var)] = container
        end
    end
    return esc(macro_code)
end

"""
    @linkconstraint(graph::OptiGraph, expr)

Add a linking constraint described by the expression `expr`.

    @linkconstraint(graph::OptiGraph, ref[i=..., j=..., ...], expr)

Add a group of linking  constraints described by the expression `expr` parametrized by
`i`, `j`, ...

The @linkconstraint macro works the same way as the `JuMP.@constraint` macro.
"""
macro linkconstraint(graph, args...)
    args, kw_args, = Containers.parse_macro_arguments(error, args)
    macro_code = quote
        @assert isa($graph, OptiGraph)
        refs = JuMP.@constraint($graph, ($(args...)))
    end
    return esc(macro_code)
end

"""
    @nodevariables(iterable, expr...)

Call the JuMP.@variable macro for each optinode in a given container
"""
macro nodevariables(nodes, args...)
    macro_code = quote
        for node in $(nodes)
            begin
                JuMP.@variable(node, $(args...))
            end
        end
    end
    return esc(macro_code)
end

# TODO: @nodeconstraints
# We would need to intercept variable arguments and lookup the actual node variables
