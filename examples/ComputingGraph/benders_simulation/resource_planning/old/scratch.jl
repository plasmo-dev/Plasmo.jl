#Test plot
# h = 0.2
# shape1 = rect(1.0, h, 0.0, 1)
# shape2 = rect(0.3, h, 0.0 + 1.0, 1)
# shape3 = rect(1.5, h, 0.0, 2)
# shape4 = rect(0.5, h, 0.0 + 1.0, 3)
#
# plt = plot(;ylim = (0,3.5))
# plot!(plt,shape1, c = :blue)
# plot!(plt,shape2, c = :red)
# plot!(plt,[1.3,1.3],[1.1,2.9],arrow = arrow(),color = :black, linealpha = 0.5, linewidth = 2.0, linestyle = :dash)
# plot!(plt,shape3, c = :blue)
# plot!(plt,shape4, c = :blue)


# @recipe function f(v::Vector{T}) where T<:IntervalBox{2}
#
#     seriestype := :shape
#
#     xs = Float64[]
#     ys = Float64[]
#
#     # build up coords:  # (alternative: use @series)
#     for xx in v
#         (x, y) = xx
#
#         # use NaNs to separate
#         append!(xs, [x.lo, x.hi, x.hi, x.lo, NaN])
#         append!(ys, [y.lo, y.lo, y.hi, y.hi, NaN])
#
#     end
#
#     alpha --> 0.5
#
#     #x = xs
#     #y = ys
#
#     #x, y
#
#     xs, ys
#
# end
