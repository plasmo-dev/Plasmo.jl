#Graph Layout functions
using NetworkLayout.SFDP
using GeometryTypes:Point2f0,Point
using Colors
using ColorTypes
using Statistics

#TODO other plotting options:  plot bipartite, node-pins, or clique-expansion
function Plots.plot(graph::ModelGraph; node_labels = false, subgraph_colors = false,node_colors = false,linewidth = 2.0,linealpha = 1.0, markersize = 30,labelsize = 20, markercolor = :grey,
    layout_options = Dict(:tol => 0.01,:C => 2, :K => 4, :iterations => 2),
    plt_options = Dict(:legend => false,:framestyle => :box,:grid => false,
    :size => (800,800),:axis => nothing),line_options = Dict(:linecolor => :blue,:linewidth => linewidth,:linealpha => linealpha),annotate_options = Dict(:markercolor => :black))

    if subgraph_colors
        markercolor = []
        n_graphs = length(graph.subgraphs) + 1
        cols = Colors.distinguishable_colors(n_graphs)
        if cols[1] == colorant"black"
            cols[1] = colorant"grey"
        end
        for node in getnodes(graph)
            push!(markercolor,cols[1])
        end
        i = 2
        for subgraph in getsubgraphs(graph)
            for node in all_nodes(subgraph)
                push!(markercolor,cols[i])
            end
            i += 1
        end

    elseif node_colors
        cols = Colors.distinguishable_colors(length(all_nodes(graph)) + 1)
        if cols[1] == colorant"black"
            cols[1] = colorant"grey"
        end
        markercolor = cols[2:end]
    else
        markercolor = markercolor
    end



    hypergraph,hyper_map = gethypergraph(graph)
    clique_graph,clique_map = clique_expansion(hypergraph)
    lgraph = clique_graph#.lightgraph


    startpositions = Array{Point{2,Float32},1}()
    for i = 1:LightGraphs.nv(lgraph)
        push!(startpositions,Point(rand(),rand()))
    end
    mat = LightGraphs.adjacency_matrix(lgraph)
    positions = SFDP.layout(mat,Point2f0,startpositions = startpositions;layout_options...)

    #marker colors should be based on subgraphs
    scat_plt = Plots.scatter(positions;markersize = markersize,markercolor = markercolor,plt_options...);

    if node_labels
        for (i,node) in enumerate(all_nodes(graph))
            pos = positions[i]
            Plots.annotate!(scat_plt,pos[1],pos[2],Plots.text(node.label,labelsize))
        end
    end

    for edge in edges(lgraph)
        n_from_index = edge.src
        n_to_index = edge.dst
        Plots.plot!(scat_plt,[positions[n_from_index][1],positions[n_to_index][1]],[positions[n_from_index][2],positions[n_to_index][2]];line_options...)
    end

    return scat_plt
end

rectangle(w, h, x, y) = Plots.Shape(x .+ [0,w,w,0], y .+ [0,0,h,h])

function Plots.spy(graph::ModelGraph;node_labels = false,labelsize = 24,subgraph_colors = false,node_colors = false)

    n_graphs = length(graph.subgraphs)
    if subgraph_colors
        cols = Colors.distinguishable_colors(n_graphs + 1)
        if cols[1] == colorant"black"
            cols[1] = colorant"grey"
        end
        colors = cols[2:end]
    else
        colors = [colorant"grey" for _= 1:n_graphs]
    end

    if node_colors
        cols = Colors.distinguishable_colors(length(all_nodes(graph)) + 1)
        if cols[1] == colorant"black"
            cols[1] = colorant"grey"
        end
        node_cols = cols[2:end]
    end
    

    #Plot limits
    n_vars_total = num_all_variables(graph)
    n_cons_total = num_all_constraints(graph)
    n_linkcons_total = num_all_linkconstraints(graph)

    n_all_cons_total = n_cons_total + n_linkcons_total #n_link_edges_total

    if n_all_cons_total >= 5
        yticks = Int64.(round.(collect(range(0,stop = n_all_cons_total,length = 5))))
    else
        yticks = Int64.(round.(collect(range(0,stop = n_all_cons_total,length = n_all_cons_total + 1))))
    end

    #Setup plot dimensions
    plt = Plots.plot(;xlims = [0,n_vars_total],ylims = [0,n_all_cons_total],legend = false,framestyle = :box,xlabel = "Node Variables",ylabel = "Constraints",size = (800,800),
    guidefontsize = 24,tickfontsize = 18,grid = false,yticks = yticks)

    #plot top level nodes, then start going down subgraphs
    n_link_constraints = num_linkconstraints(graph)  #local links
    col = 0
    node_indices = Dict()
    node_col_ranges = Dict()
    for (i,node) in enumerate(all_nodes(graph))
        node_indices[node] = i
        node_col_ranges[node] = [col,col + num_variables(node)]
        col += num_variables(node)
    end

    row = n_all_cons_total  - n_link_constraints #- height_initial
    #draw node blocks for this graph
    for (i,node) in enumerate(getnodes(graph))
        height = num_constraints(node)
        row -= height
        #row_start,row_end = node_row_ranges[node]
        row_start = row
        col_start,col_end = node_col_ranges[node]
        width = col_end - col_start

        row_end = row - height
        rec = rectangle(width,height,col_start,row_start)

        if !(node_colors)
            Plots.plot!(plt,rec,opacity = 1.0,color = :grey)
        else
            Plots.plot!(plt,rec,opacity = 1.0,color = node_cols[i])
        end
        if node_labels
            Plots.annotate!(plt,(col_start + width + col_start)/2,(row + height + row)/2,Plots.text(node.label,labelsize))
        end
    end

    #plot link constraints for highest level using rectangles
    row = n_all_cons_total
    #recs = []

    link_rows = []
    link_cols = []
    for link in getlinkconstraints(graph)
        row -= 1
        vars = keys(link.func.terms)
        for var in vars
            node = getnode(var)

            col_start,col_end = node_col_ranges[node]
            col_start = col_start + var.index.value - 1

            #these are just points.
            #rec = rectangle(1,1,col_start,row)
            push!(link_rows,row)
            push!(link_cols,col_start)
            # Plots.plot!(plt,rec,opacity = 1.0,color = :blue);
        end

    end
    Plots.scatter!(plt,link_cols,link_rows,markersize = 1,markercolor = :blue,markershape = :rect);

    row -= 1
    _plot_subgraphs!(graph,plt,node_col_ranges,row,node_labels = node_labels,labelsize = labelsize,colors = colors)
    return plt
end

function _plot_subgraphs!(graph::ModelGraph,plt,node_col_ranges,row_start_graph;node_labels = false,labelsize = 24,colors = nothing)
    if colors == nothing
        colors = [colorant"grey" for _= 1:length(graph.subgraphs)]
    end


    row_start_graph = row_start_graph
    for (i,subgraph) in enumerate(getsubgraphs(graph))


        link_rows = []
        link_cols = []
        row = row_start_graph#

        for link in getlinkconstraints(subgraph)
            row -= 1
            #nodes = getnodes(link)
            vars = keys(link.func.terms)
            for var in vars
                node = getnode(var)
                col_start,col_end = node_col_ranges[node]
                col_start = col_start + var.index.value - 1
                # rec = rectangle(1,1,col_start,row)
                # Plots.plot!(plt,rec,opacity = 1.0,color = :blue)
                push!(link_rows,row)
                push!(link_cols,col_start)
            end
        end
        Plots.scatter!(plt,link_cols,link_rows,markersize = 1,markercolor = :blue,markershape = :rect);

        if !(isempty(subgraph.modelnodes))
            subgraph_col_start = node_col_ranges[subgraph.modelnodes[1]][1]
        else
            subgraph_col_start = 0
        end

        #draw node blocks for this graph
        for node in getnodes(subgraph)
            height = num_constraints(node)
            row -= height
            row_start = row
            col_start,col_end = node_col_ranges[node]
            width = col_end - col_start

            rec = rectangle(width,height,col_start,row_start)
            Plots.plot!(plt,rec,opacity = 1.0,color = colors[i])
            if node_labels
                Plots.annotate!(plt,(col_start + width + col_start)/2,(row + height + row)/2,Plots.text(node.label,labelsize))
            end

        end

        _plot_subgraphs!(subgraph,plt,node_col_ranges,row,node_labels = node_labels,labelsize = labelsize)

        num_cons = num_all_constraints(subgraph) + num_all_linkconstraints(subgraph)
        num_vars = num_all_variables(subgraph)
        row_start_graph -= num_cons
        subgraph_row_start = row_start_graph

        rec = rectangle(num_vars,num_cons,subgraph_col_start,subgraph_row_start)
        Plots.plot!(plt,rec,opacity = 0.1,color = colors[i])

    end
end


#Overlap plots

function Plots.plot(graph::ModelGraph,subgraphs::Vector{ModelGraph}; node_labels = false,linewidth = 2.0, linealpha = 1.0,markersize = 30,labelsize = 20, markercolor = :grey,
    layout_options = Dict(:tol => 0.01,:C => 2, :K => 4, :iterations => 2), plt_options = Dict(:legend => false,:framestyle => :box,:grid => false,
    :size => (800,800),:axis => nothing),line_options = Dict(:linecolor => :blue,:linewidth => linewidth,:linealpha => linealpha),annotate_options = Dict(:markercolor => :black))

    nodes = all_nodes(graph)


    #COLORS
    markercolors = []
    markersizes = []
    n_graphs = length(subgraphs)
    cols = Colors.distinguishable_colors(n_graphs)
    if cols[1] == colorant"black"
        cols[1] = colorant"grey"
    end

    #subgraph_colors = Dict()
    node_colors = Dict((node,[]) for node in all_nodes(graph))


    for (i,subgraph) in enumerate(subgraphs)
        for node in all_nodes(subgraph)
            push!(node_colors[node],cols[i])
        end
    end

    #Now average node colors
    for node in all_nodes(graph)
        if haskey(node_colors,node)
            node_cols = node_colors[node]
            ave_r = mean([node_cols[i].r for i = 1:length(node_cols)])
            ave_g = mean([node_cols[i].g for i = 1:length(node_cols)])
            ave_b = mean([node_cols[i].b for i = 1:length(node_cols)])

            new_col = RGB(ave_r,ave_g,ave_b)
            push!(markercolors,new_col)
            if length(node_cols) > 1
                push!(markersizes,markersize*2)
            else
                push!(markersizes,markersize)
            end
        else
            push!(markercolors,colorant"grey")
            push!(markersizes,markersize)
        end
    end


    #LAYOUT
    hypergraph,hyper_map = gethypergraph(graph)
    clique_graph,clique_map = clique_expansion(hypergraph)
    lgraph = clique_graph#.lightgraph


    startpositions = Array{Point{2,Float32},1}()
    for i = 1:LightGraphs.nv(lgraph)
        push!(startpositions,Point(rand(),rand()))
    end
    mat = LightGraphs.adjacency_matrix(lgraph)
    positions = SFDP.layout(mat,Point2f0,startpositions = startpositions;layout_options...)

    #marker colors should be based on subgraphs
    scat_plt = Plots.scatter(positions;markersize = markersizes,markercolor = markercolors,plt_options...);

    if node_labels
        for (i,node) in enumerate(all_nodes(graph))
            pos = positions[i]
            Plots.annotate!(scat_plt,pos[1],pos[2],Plots.text(node.label,labelsize))
        end
    end

    for edge in edges(lgraph)
        n_from_index = edge.src
        n_to_index = edge.dst
        Plots.plot!(scat_plt,[positions[n_from_index][1],positions[n_to_index][1]],[positions[n_from_index][2],positions[n_to_index][2]];line_options...)
    end

    return scat_plt
end

function Plots.spy(graph::ModelGraph,subgraphs::Vector{ModelGraph};node_labels = false,labelsize = 24,subgraph_colors = true)

    n_graphs = length(subgraphs)
    if subgraph_colors
        cols = Colors.distinguishable_colors(n_graphs + 1)
        if cols[1] == colorant"black"
            cols[1] = colorant"grey"
        end
        colors = cols[2:end]
    else
        colors = [colorant"grey" for _= 1:n_graphs]
    end

    #Plot limits
    n_vars_total = sum(num_variables.(subgraphs)) #+ sum(num_variables.(getnodes(graph))) #master
    n_cons_total = sum(num_all_constraints.(subgraphs)) #+ sum(num_constraints.(getnodes(graph))) #+ num_linkconstraints(graph)
    n_linkcons_total = sum(num_all_linkconstraints.(subgraphs)) #+ num_all_linkconstraints(graph)

    n_all_cons_total = n_cons_total + n_linkcons_total

    if n_all_cons_total >= 5
        yticks = Int64.(round.(collect(range(0,stop = n_all_cons_total,length = 5))))
    else
        yticks = Int64.(round.(collect(range(0,stop = n_all_cons_total,length = n_all_cons_total + 1))))
    end

    #Setup plot dimensions
    plt = Plots.plot(;xlims = [0,n_vars_total],ylims = [0,n_all_cons_total],legend = false,framestyle = :box,xlabel = "Node Variables",ylabel = "Constraints",size = (800,800),
    guidefontsize = 24,tickfontsize = 18,grid = false,yticks = yticks)

    row_start_graph = n_all_cons_total - 1
    col_start_graph = 1
    for i = 1:length(subgraphs)
        subgraph = subgraphs[i]
        #column data for subgraph
        node_indices = Dict()
        node_col_ranges = Dict()

        col = col_start_graph
        for (i,node) in enumerate(all_nodes(subgraph))
            node_indices[node] = i
            node_col_ranges[node] = [col,col + num_variables(node)]
            col += num_variables(node)
        end

        #Now just plot columns of overlap nodes
        nodes = all_nodes(subgraph)
        overlap_nodes = Dict()
        for j = 1:length(subgraphs)
            if j != i
                other_subgraph = subgraphs[j]
                other_nodes = all_nodes(other_subgraph)
                overlap = intersect(nodes,other_nodes)
                overlap_nodes[j] = overlap
            end
        end
                #plot local column overlap
        link_rows = []
        link_cols = []
        row = row_start_graph
        for link in getlinkconstraints(subgraph)
            row -= 1
            vars = keys(link.func.terms)
            for var in vars
                node = getnode(var)
                col_start,col_end = node_col_ranges[node]
                col_start = col_start + var.index.value - 1
                push!(link_rows,row)
                push!(link_cols,col_start)
            end
        end
        Plots.scatter!(plt,link_cols,link_rows,markersize = 1,markercolor = :blue,markershape = :rect);

        #draw node blocks for this graph
        for node in getnodes(subgraph)
            height = num_constraints(node)
            row -= height
            row_start = row
            col_start,col_end = node_col_ranges[node]
            width = col_end - col_start

            rec = rectangle(width,height,col_start,row_start)
            Plots.plot!(plt,rec,opacity = 1.0,color = colors[i])
            if node_labels
                Plots.annotate!(plt,(col_start + width + col_start)/2,(row + height + row)/2,Plots.text(node.label,labelsize))
            end
        end

        num_cons = num_all_constraints(subgraph) + num_all_linkconstraints(subgraph)
        num_vars = num_all_variables(subgraph)

        subgraph_plt_start = row
        rec = rectangle(num_vars,num_cons,col_start_graph,subgraph_plt_start)
        Plots.plot!(plt,rec,opacity = 0.1,color = colors[i])

        #overlap rectanges
        for (j,overlap) in overlap_nodes
            for node in overlap
                col_start,col_end = node_col_ranges[node]
                rec = rectangle(num_variables(node),num_cons,col_start,subgraph_plt_start)
                Plots.plot!(plt,rec,opacity = 0.1,color = colors[j])
            end
        end

        col_start_graph = col
        row_start_graph = row
    end

    return plt
end
