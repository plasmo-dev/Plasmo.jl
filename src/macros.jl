using Base.Meta

"""
    @optinode(optigraph, expr...)

Add a new optinode to `optigraph`. The expression `expr` can either be

* of the form `nodename` creating a single optinode with the variable name `varname`
* of the form `nodename[...]` or `[...]` creating a container of optinodes using JuMP Containers

"""
macro optinode(graph,args...)
     _error(str...) = JuMP._macro_error(:node, args, str...)

    @assert length(args) <= 1
    extra = collect(args)

    if length(extra) == 0
        x = gensym()
    else
        x = popfirst!(extra)
    end
    nodeexpr = x

    name = _get_name(nodeexpr)
    namekey = string(name)
    node = gensym()

    if isa(nodeexpr, Symbol) # Easy case - a single node
        nodecall = :(add_node!($graph))
        macro_code = :($name = $nodecall)
    else
        isa(nodeexpr, Expr) || _error("Expected $node to be a node name")

        # We now build the code to generate the optinodes
        idxnodes, indices = _build_ref_sets(nodeexpr, node)
        container_code = JuMP.Containers.generate_container(OptiNode,idxnodes,indices,:Auto)
        macro_code = quote
            $name = $(container_code[1])
            if isa($name,JuMP.Containers.DenseAxisArray)
                for index in 1:length($name.data)
                    $name.data[index] = add_node!($graph;label = $(namekey)*"$index")
                end
            else
                for index in 1:length($name)
                    $name[index] = add_node!($graph;label = $(namekey)*"[$index]")
                end
            end
            $graph.obj_dict[Symbol($namekey)] = $name
        end
    end
    return esc(macro_code)
end

macro node(graph,args...)
    code = quote
        @warn "@node is deprecated.  Use @optinode for future applications"
        @optinode($graph,$(args...))
    end
    return esc(code)
end


"""
    @linkconstraint(graph::OptiGraph, expr)

Add a linking constraint described by the expression `expr`.

    @linkconstraint(graph::OptiGraph, ref[i=..., j=..., ...], expr)

Add a group of linking  constraints described by the expression `expr` parametrized by
`i`, `j`, ...

The @linkconstraint macro works the same way as the `JuMP.@constraint` macro.
"""
macro linkconstraint(graph_or_edge,args...)
    args, kw_args, requestedcontainer = Containers._extract_kw_args(args)
    attached_node_kw_args = filter(kw -> kw.args[1] == :attach, kw_args)
    #mpi_kw_args = filter(kw -> kw.args[1] == :mpi, kw_args)
    #extra_kw_args = filter(kw -> kw.args[1] != :attach, kw_args)

    #check for attached node argumentss
    if length(attached_node_kw_args) > 0
        attached_node = attached_node_kw_args[1].args[2]
    else
        attached_node = nothing
    end

    # #check for mpi arguments
    # if length(mpi_kw_args) > 0
    #     mpi = mpi_kw_args[1].args[2]
    # else
    #     mpi = false
    # end

    #Manipulate args if mpi is true

    code = quote
        @assert isa($graph_or_edge,Union{AbstractOptiGraph,OptiEdge})  #Check the inputs are the correct types.  This needs to throw


        refs = JuMP.@constraint($graph_or_edge,($(args...)))

        #BUG: need to unfold attached node arguments.  It isn't grabbing the correct
        #Set attached node if argument was provided
        if $attached_node != nothing
            if isa(refs,LinkConstraintRef)
                link = LinkConstraint(refs)
                set_attached_node(link,$attached_node)
            else
                links = LinkConstraint.(refs)
                for link in links
                    set_attached_node(link,$attached_node)
                end
            end
        end
        refs
    end
    return esc(code)
end

"""
    @NLnodeconstraint(node,args...)

Add a nonlinear constraint to an optinode.  Wraps JuMP.@NLconstraint.  This method will deprecate once optinodes
extend nonlinear JuMP functionality.
"""
macro NLnodeconstraint(node,args...)
    code = quote
        @warn "@NLnodeconstraint is deprecated.  Use @NLconstraint for future applications"
        JuMP.@NLconstraint($node,($(args...)))
    end
    return esc(code)
end

macro NLnodeobjective(node,args...)
    code = quote
        @warn "@NLnodeobjective is deprecated.  Use @NLobjective for future applications"
        JuMP.@NLobjective($node,($(args...)))
    end
    return esc(code)
end
#macro function helpers
function _build_ref_sets(expr::Expr, cname)
    c = copy(expr)
    idxvars = Any[]
    idxsets = Any[]
    # Creating an indexed set of refs
    # On 0.7, :(t[i;j]) is a :ref, while t[i,j;j] is a :typed_vcat.
    # In both cases :t is the first arg.
    if isexpr(c, :typed_vcat) || isexpr(c, :ref)
        popfirst!(c.args)
    end

    for s in c.args
        parse_done = false
        if isa(s, Expr)
            parse_done, idxvar, _idxset = _try_parse_idx_set(s::Expr)
            if parse_done
                idxset = _idxset
            end
        end
        if !parse_done # No index variable specified
            idxvar = gensym()
            idxset = s
        end
        push!(idxvars, idxvar)
        push!(idxsets, idxset)
    end
    return idxvars, idxsets
end

_build_ref_sets(c, cname)  = (cname, Any[], Any[], :())
_build_ref_sets(c) = _build_ref_sets(c, _get_name(c))

function _try_parse_idx_set(arg::Expr)
    # [i=1] and x[i=1] parse as Expr(:vect, Expr(:(=), :i, 1)) and
    # Expr(:ref, :x, Expr(:kw, :i, 1)) respectively.
    if arg.head === :kw || arg.head === :(=)
        @assert length(arg.args) == 2
        return true, arg.args[1], arg.args[2]
    elseif isexpr(arg, :call) && arg.args[1] === :in
        return true, arg.args[2], arg.args[3]
    else
        return false, nothing, nothing
    end
end

function _parse_idx_set(arg::Expr)
    parse_done, idxvar, idxset = _try_parse_idx_set(arg)
    if parse_done
        return idxvar, idxset
    end
    error("Invalid syntax: $arg")
end

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

#TODO: parallel model building
#@blas_safe_threads
# const blas_num_threads = Ref{Int}()
# function set_blas_num_threads(n::Integer;permanent::Bool=false)
#     permanent && (blas_num_threads[]=n)
#     BLAS.set_num_threads(n) # might be mkl64 or openblas64
#     ccall((:mkl_set_dynamic, libmkl32),
#           Cvoid,
#           (Ptr{Int32},),
#           Ref{Int32}(0))
#     ccall((:mkl_set_num_threads, libmkl32),
#           Cvoid,
#           (Ptr{Int32},),
#           Ref{Int32}(n))
#     ccall((:openblas_set_num_threads, libopenblas32),
#           Cvoid,
#           (Ptr{Int32},),
#           Ref{Int32}(n))
# end
# macro blas_safe_threads(args...)
#     code = quote
#         set_blas_num_threads(1)
#         Threads.@threads($(args...))
#         set_blas_num_threads(blas_num_threads[])
#     end
#     return esc(code)
# end

# macro NLnodeconstraint(node,args...)
#     code = quote
#         @assert isa($node,OptiNode)  #Check the inputs are the correct types.  This needs to throw
#         JuMP.@NLconstraint((getmodel($node)),($(args...)))  #link model extends @constraint macro
#     end
#     return esc(code)
# end

# macro NLnodeobjective(node,args...)
#     code = quote
#         @assert isa($node,OptiNode)  #Check the inputs are the correct types.  This needs to throw
#         JuMP.@NLobjective((getmodel($node)),($(args...)))  #link model extends @constraint macro
#     end
#     return esc(code)
# end
