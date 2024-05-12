function JuMP.list_of_constraint_types(obj::OptiObject)::Vector{Tuple{Type,Type}}
    # NOTE from JuMP:
    # We include an annotated return type here because Julia fails terribly at
    # inferring it, even though we annotate the type of the return vector.
    return Tuple{Type,Type}[
        (JuMP.jump_function_type(obj, F), S) for
        (F, S) in MOI.get(obj, MOI.ListOfConstraintTypesPresent())
    ]
end

function JuMP.num_constraints(
    node::OptiNode,
    function_type::Type{
        <:Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}},
    },
    set_type::Type{<:MOI.AbstractSet},
)::Int64
    F = JuMP.moi_function_type(function_type)
    return MOI.get(graph_backend(node), MOI.NumberOfConstraints{F,set_type}(), node)
end


# function JuMP.num_constraints(
#     element::OptiElement,
#     ::Type{F}, 
#     ::Type{S}
# )::Int64 where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
#     g2n = graph_backend(element).graph_to_element_map
#     cons = MOI.get(element, MOI.ListOfConstraintIndices{F,S}())
#     constraint_refs = [g2n[con] for con in cons]
#     return length(filter((cref) -> cref.model == element, constraint_refs))
# end