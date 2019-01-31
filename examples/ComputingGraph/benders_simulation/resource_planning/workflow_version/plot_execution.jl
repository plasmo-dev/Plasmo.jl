using Plots
pyplot()
#Plots.scalefontsizes(1.5)
using ColorSchemes
task_scheme = ColorSchemes.Accent_3
# nodes = collectnodes(workflow)

rect(w, h, x, y) = Shape(x + [0,w,w,0], (y - 0.5*h)  + [0,0,h,h])

function create_workflow_plot(workflow::Workflow,master_node::DispatchNode,sub_nodes::Vector,channels::Vector)

    nodes = [master_node;sub_nodes]

    plot_nodes = nodes
    if length(nodes) > 7
        plot_nodes = [sub_nodes[1:3];master_node;sub_nodes[4:end]]
    end
    if length(nodes) > 15
        plot_nodes = [sub_nodes[1:7];master_node;sub_nodes[8:end]]
    end

    final_time = getcurrenttime(workflow)

    #Assume I have the channels
    plt = plot(;xlabel = "Time [s]" , ylabel = "Compute Node",legend = :topright,ylim = (0,length(nodes) + 1),grid = true)
    bar_height = 0.2
    j = 1
    node_map = Dict()

    tasks = unique([collect(keys(node.node_tasks))[i] for node in nodes for i in 1:length(node.node_tasks)])
    n_tasks = length(tasks)
    #map tasks to colors
    task_colors = Dict()
    i = 1
    for task in tasks
        task_colors[task] = get(task_scheme,i/n_tasks)
        i += 1
    end

    checked_tasks = []
    for node in plot_nodes


        node_map[node] = j

        track_shape = rect(final_time,bar_height,0,j)
        plot!(plt,track_shape,alpha = 0.05,c = :green,label = "")

        history = node.history
        for action in history
            time = action[1]
            task = action[2]
            duration = action[3]

            new_task = false
            if !(task in checked_tasks)
                new_task = true
                push!(checked_tasks,task)
            end

            if new_task == true
                label = task
            else
                label = ""
            end

            if duration > 0
                shape = rect(duration,bar_height,time,j)
                plot!(plt,shape,c = task_colors[task],label = label)
            else
                scatter!(plt,[time],[j],label = label, c = task_colors[task])
            end
        end
        j += 1
    end

    for channel in channels
        from_node = channel.from_attribute.node
        to_node = channel.to_attribute.node
        history = channel.history
        for comm in history
            time = comm[1]
            duration = comm[2]
            arrow_x = [time,time+duration]
            if node_map[from_node] < node_map[to_node]
                arrow_y = [node_map[from_node] + 0.5*bar_height,node_map[to_node] - 0.5*bar_height]
            elseif node_map[from_node] > node_map[to_node]
                arrow_y = [node_map[from_node] - 0.5*bar_height,node_map[to_node] + 0.5*bar_height]
            end
            plot!(plt,arrow_x,arrow_y,arrow = arrow(),label = "", color = :grey, linealpha = 0.3, linewidth = 1.5, linestyle = :dash)
        end
    end

    return plt
end
