#Create a single feeder task that runs a simple task in a loop using remotecall_fetch or @spawn

#addprocs(4)

@everywhere function simple_task(i)
    #i = i + 1
    #println(i)
    return i*2
end


#tasks = []
results = []
@time begin
#@schedule begin
#@async begin       #our local feeder task
    i = 1
    while true     #feeder task runs in continuous loop
        #result = remotecall_fetch(simple_task,1,i)   #runs simple_task with argument i on the prescribed process (1) and fetches the result
        result = @spawn simple_task(i)               #spawns simple_task on an available process and returns a Future
        #result = @schedule simple_task(i)             #schedules the task on the local scheduler queue.  Use yield() to start the task in the loop?
        #yield()
        push!(results,result)
        #println(result)
        #println(fetch(result))
        #push!(tasks,t)
        #wait(s)
        #i = fetch(s)
        i += 1
        if i > 5
            break
        end
    end
#end
end
