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

function _plasmo_finalize_macro(
    model::Expr,
    code::Any,
    source::LineNumberNode;
    register_name::Union{Nothing,Symbol} = nothing,
    wrap_let::Bool = false,
    time_it::Union{Nothing,String} = nothing,
)
    @assert Meta.isexpr(model, :escape)
    ret = gensym()
    code = if wrap_let && model.args[1] isa Symbol
        quote
            $ret = let $model = $model
                $code
            end
        end
    else
        :($ret = $code)
    end
    if register_name !== nothing
        sym_name = Meta.quot(register_name)
        code = quote
            $code
        end
    end
    if time_it !== nothing
        code = quote
            start_time = time()
            $code
            JuMP._add_or_set_macro_time(
                $model,
                ($(QuoteNode(source)), $time_it),
                time() - start_time,
            )
            $ret
        end
    end
    is_valid_code = :()
    return Expr(:block, source, is_valid_code, code)
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
    kwargs = Dict{Symbol, Any}()
    if isempty(args)
        macro_code = :(add_node($graph))
        return esc(macro_code)
    elseif isa(graph, Plasmo.OptiGraph)
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
        return esc(macro_code)
    else
        #get the name passed into the macro expression
        error_fn = JuMP.Containers.build_error_fn(:optinode, args, __source__)
        name, index_vars, indices = Containers.parse_ref_sets(error_fn, args[1])
        graph = esc(graph)
        name_expr = JuMP.Containers.build_name_expr(name, index_vars, kwargs)

        macro_code = JuMP.Containers.container_code(
            index_vars,
            indices,
            quote
                add_node($graph, Symbol($name_expr))
            end,
            kwargs,
        )
        println(typeof(macro_code))
        macro_expr = _plasmo_finalize_macro(
            graph, 
            macro_code, 
            __source__, 
            register_name = name, 
            wrap_let = false,
            time_it = Containers.build_macro_expression_string(
                :optinode,
                args,
            )
        )
        return esc(macro_expr)
    end
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
        @assert isa($graph, Plasmo.AbstractOptiGraph)
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
