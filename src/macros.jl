#macro function helpers
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
    var = Base.string(_get_name(args[1]))

    #get the name passed into the macro expression
    # if typeof(args[1]) == Symbol
    #     macro_code = :(add_node($graph); label=Symbol($var))
    # else
    macro_code = quote
        container = JuMP.Containers.@container($(args...), add_node($graph))
        #set node labels
        # if isa(container, Plasmo.OptiNode)
        #     container.label = $var
        # TODO: decide whether we want node labels to match macro input
        # else
        #     axs = axes(container)
        #     terms = collect(Base.Iterators.product(axs...))[:]
        #     for (i, node) in enumerate(container)
        #         node.label = Symbol($var * "[$(string(terms[i]...))]")
        #     end
        #end
        $(graph).obj_dict[Symbol($var)] = container
    end
    # end
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
    args, kw_args, requestedcontainer = Containers._extract_kw_args(args)
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
