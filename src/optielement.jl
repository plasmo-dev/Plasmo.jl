# JuMP methods that dispatch on both optinodes and optiedges

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
    idx::MOI.ConstraintIndex{<:MOI.AbstractScalarFunction, <:MOI.AbstractScalarSet}
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
    function_type::Type{
        <:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}},
    },
    set_type::Type{<:MOI.AbstractSet}
)::Int64
    F = JuMP.moi_function_type(function_type)
    return MOI.get(element, MOI.NumberOfConstraints{F,set_type}())
end

function JuMP.all_constraints(
    element::OptiElement,
    func_type::Type{
        <:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}},
    },
    set_type::Type{<:MOI.AbstractSet},
)
    F = JuMP.moi_function_type(func_type)
    if set_type <: MOI.AbstractScalarSet
        constraint_ref_type = JuMP.ConstraintRef{
            typeof(element),
            MOI.ConstraintIndex{F,set_type},
            ScalarShape,
        }
    else
        constraint_ref_type =
            ConstraintRef{typeof(element),MOI.ConstraintIndex{F,set_type}}
    end
    result = constraint_ref_type[]
    for idx in MOI.get(element, MOI.ListOfConstraintIndices{F,set_type}())
        push!(result, JuMP.constraint_ref_with_index(element, idx))
    end
    return result
end
