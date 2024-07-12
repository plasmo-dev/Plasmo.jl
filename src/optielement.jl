# JuMP & MOI methods that dispatch on both optinodes and optiedges

#
# MOI Methods
#

function MOI.get(element::OptiElement, attr::MOI.AnyAttribute, args...)
    return MOI.get(graph_backend(element), attr, element)
end

function MOI.set(element::OptiElement, attr::MOI.AnyAttribute, args...)
    for graph in containing_optigraphs(element)
        MOI.set(graph_backend(element), attr, element, args...)
    end
end

function MOI.get(
    element::OptiElement, attr::AT, cref::ConstraintRef
) where {AT<:MOI.AbstractConstraintAttribute}
    return MOI.get(graph_backend(element), attr, cref)
end

function MOI.set(
    element::OptiElement, attr::AT, cref::ConstraintRef, args...
) where {AT<:MOI.AbstractConstraintAttribute}
    for graph in containing_optigraphs(element)
        MOI.set(graph_backend(element), attr, cref, args...)
    end
    return nothing
end

function MOI.delete(element::OptiElement, cref::ConstraintRef)
    for graph in containing_optigraphs(element)
        MOI.delete(graph_backend(graph), cref)
    end
    return nothing
end

#
# JuMP Methods
#

"""
    JuMP.constraint_ref_with_index(
    element::OptiElement, 
    idx::MOI.ConstraintIndex{<:MOI.AbstractScalarFunction, <:MOI.AbstractScalarSet}
    )

Return a `ConstraintRef` given an optigraph element and `MOI.ConstraintIndex`. 
Note that the index is the index corresponding to the graph backend, not the element index.
"""
function JuMP.constraint_ref_with_index(
    element::OptiElement,
    idx::MOI.ConstraintIndex{<:MOI.AbstractScalarFunction,<:MOI.AbstractScalarSet},
)
    return JuMP.constraint_ref_with_index(graph_backend(element), idx)
end

function JuMP.constraint_ref_with_index(element::OptiElement, idx::MOI.VariableIndex)
    return JuMP.constraint_ref_with_index(graph_backend(element), idx)
end

function JuMP.list_of_constraint_types(element::OptiElement)::Vector{Tuple{Type,Type}}
    # NOTE from JuMP:
    # We include an annotated return type here because Julia fails terribly at
    # inferring it, even though we annotate the type of the return vector.
    return Tuple{Type,Type}[
        (JuMP.jump_function_type(element, F), S) for
        (F, S) in MOI.get(element, MOI.ListOfConstraintTypesPresent())
    ]
end

"""
    JuMP.num_constraints(
    element::OptiElement,
    function_type::Type{
        <:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}},
    },set_type::Type{<:MOI.AbstractSet})::Int64

Return the total number of constraints on an element.
"""
function JuMP.num_constraints(
    element::OptiElement,
    function_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)::Int64
    F = JuMP.moi_function_type(function_type)
    return MOI.get(element, MOI.NumberOfConstraints{F,set_type}())
end

function JuMP.num_constraints(
    element::OptiElement;
    count_variable_in_set_constraints=true
)::Int64
    num_cons = 0
    con_types = JuMP.list_of_constraint_types(element)
    for con_type in con_types
        function_type = con_type[1]
        set_type = con_type[2]
        if function_type == NodeVariableRef && count_variable_in_set_constraints == false
            continue
        end
        num_cons += JuMP.num_constraints(element, function_type, set_type)
    end
    return num_cons
end

function JuMP.all_constraints(
    element::OptiElement,
    func_type::Type{<:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}}},
    set_type::Type{<:MOI.AbstractSet},
)
    F = JuMP.moi_function_type(func_type)
    if set_type <: MOI.AbstractScalarSet
        constraint_ref_type = JuMP.ConstraintRef{
            typeof(element),MOI.ConstraintIndex{F,set_type},ScalarShape
        }
    else
        constraint_ref_type = ConstraintRef{typeof(element),MOI.ConstraintIndex{F,set_type}}
    end
    result = constraint_ref_type[]
    for idx in MOI.get(element, MOI.ListOfConstraintIndices{F,set_type}())
        push!(result, JuMP.constraint_ref_with_index(element, idx))
    end
    return result
end

function JuMP.all_constraints(
    element::OptiElement; 
    include_variable_in_set_constraints=true
)
    constraints = ConstraintRef[]
    con_types = JuMP.list_of_constraint_types(element)
    for con_type in con_types
        function_type = con_type[1]
        set_type = con_type[2]
        if function_type == NodeVariableRef && include_variable_in_set_constraints == false
            continue
        end
        append!(constraints, JuMP.all_constraints(element, function_type, set_type))
    end
    return constraints
end
