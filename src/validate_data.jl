using Dates
using DataStructures
using Predicer


# The functions of this file are used to check the validity of the imported input data,
# which at this time should be mostly in struct form

# Check list for errors:

    # x Topologies:
    # x Process sink: commodity (ERROR) 
    # x Process (non-market) sink: market (ERROR)
    # x Process (non-market) source: market (ERROR)
    # x Conversion 2 and several branches (ERROR)
    # x Source in CF process (ERROR)
    # x Conversion 1 and neither source nor sink is p (error?)
    # x Conversion 2( transport?) and several topos
    # x Conversion 2 and itself as source/sink

    # Reserve in CF process
    # Check integrity of timeseries - Checked model timesteps. 
    # Check that there is equal amount of scenarios at all points - accessing an non-existing scenario returns the first defined scenario instead. 
    # Check that each entity doesn't have several timeseries for the same scenario!
    # x Check that two entities don't have the same name.
    # Check that state min < max, process min < max, etc. 

    # Check that each node with is_res has a corresponding market.
    # 

    # Check that each of the nodes and processes is valid. 

    # Ensure that the min_online and min_offline parameter can be divided with dtf, the time between timesteps. 
    # otherwise a process may need to be online or offline for 1.5 timesteps, which is difficult to solve. 

    # In constraints, chekc if e.g. v_start even exists before trying to force start constraints. 
    # Chewck that all given values have reasonable values, ramp values >0 for example. 

    # Check that a process doesnät participate in two energy markets at the same time 
    # - should this be allowed, since the energy markets can be "blocked" using gen_constraints?
    # - Process should be fine, as long as topos are different. 

    # Check that each entity (node, process, market, etc) has all relevant information defined. 

    # Check that a process is connected to a node in the given node group during market participation
    # 
    # Check that the "node" connected to an energy market is a node, and that the 
    # "node connected to a reserve market is a nodegroup. 
    # Check that each node/process which is part of a node/process group referenced by a reserve has is_res
    # Check that the node/process group of a reserve exists
    # Check that the groups are not empty

    # check that reserve processes and reserve nodes match, so that the processes of a reserve product process group
    # actually connect to the nodes in the reserve nodegroup. Issue an warning if this isn't the case?
    # check that the processes in groups that are linked to reserves are all is_res?
    
    

function validate_inflow_blocks(error_log::OrderedDict, input_data::Predicer.InputData)
    is_valid = error_log["is_valid"] 
    blocks = input_data.inflow_blocks
    nodes = input_data.nodes
    for b in collect(keys(blocks))
        if !(blocks[b].node in collect(keys(nodes)))
            # Check that the linked nodes exist, and that they are of the correct type
            push!(error_log["errors"], "The Node linked to the block (" * b * ", " * blocks[b].node * ") is not found in Nodes.\n")
            is_valid = false 
        else
            # Check that the linked node is of the correct type (not market or commodity)
            if nodes[blocks[b].node].is_market
                push!(error_log["errors"], "A market Node ("* blocks[b].node *") cannot be linked to a inflow block ("* b *").\n")
                is_valid = false 
            elseif nodes[blocks[b].node].is_commodity
                push!(error_log["errors"], "A commodity Node ("* blocks[b].node *") cannot be linked to a inflow block ("* b *").\n")
                is_valid = false 
            end
        end

        # check that there aren't two series for the same scenario
        if length(blocks[b].data.ts_data) != length(unique(map(x -> x.scenario, blocks[b].data.ts_data)))
            push!(error_log["errors"], "Inflow block (" * b * ") has multiple series for the same scenario.\n")
            is_valid = false 
        end

        for timeseries in blocks[b].data.ts_data
            ts = map(x -> x[1], timeseries.series)
            # Check that the timesteps in the block are unique
            if length(unique(ts)) != length(ts)
                push!(error_log["errors"], "Inflow block (" * b * ") timeseries data should only contain unique timesteps.\n")
                is_valid = false 
            end

            # Check that ALL the timesteps in the block are either not found in temporals, or ALL found in the temporals. 
            for i in 1:length(ts)
                if (ts[i] in input_data.temporals.t) != (ts[1] in input_data.temporals.t)
                    push!(error_log["errors"], "The timesteps of the block (" * b * ") should either all be found, or all not found in temporals. No partial blocks allowed.\n")
                    is_valid = false 
                end
            end
        end
    end
    error_log["is_valid"] = is_valid
end

function validate_groups(error_log::OrderedDict, input_data::Predicer.InputData)
    is_valid = error_log["is_valid"] 
    processes = input_data.processes
    nodes = input_data.nodes
    groups = input_data.groups

    for g in collect(keys(groups))
        # check that the groupnames are  not the same as any process, node
        if g in [collect(keys(processes)); collect(keys(nodes))  ]
            push!(error_log["errors"], "Invalid Groupname: ", g, ". The groupname must be unique and different from any node or process names.\n")
            is_valid = false 
        end
        # check that node groups have nodes and process groups have processes
        for m in groups[g].members
            if groups[g].type == "node"
                # check that node groups have nodes and process groups have processes
                if !(m in collect(keys(nodes))  )
                    push!(error_log["errors"], "Nodegroups (" * g * ") can only have Nodes as members!\n")
                    is_valid = false 
                end
            elseif groups[g].type == "process"
                # check that node groups have nodes and process groups have processes
                if !(m in collect(keys(processes)))
                    push!(error_log["errors"], "Processgroups (" * g * ") can only have Processes as members!\n")
                    is_valid = false 
                end
            end
        end
    end

    # Check that each entity in a groups member has the group as member
    for g in collect(keys(groups))
        for m in groups[g].members
            if m in collect(keys(nodes))
                if !(g in nodes[m].groups)
                    push!(error_log["errors"], "The member (" * m * ") of a nodegroup must have the group given in node.groups!\n")
                    is_valid = false 
                end
            elseif m in collect(keys(processes))
                if !(g in processes[m].groups)
                    push!(error_log["errors"], "The member (" * m * ") of a processgroup must have the group given in process.groups!\n")
                    is_valid = false 
                end
            end
        end
    end

    # check that each process and each node is part of a group of the correct type..
    for n in collect(keys(nodes))
        for ng in nodes[n].groups
            if !(groups[ng].type == "node")
                push!(error_log["errors"], "Nodes (" * n * ") can only be members of Nodegroups, not Processgroups!\n")
                is_valid = false 
            end
        end
    end
    for p in collect(keys(processes))
        for pg in processes[p].groups
            if !(groups[pg].type == "process")
                push!(error_log["errors"], "Processes (" * p * ") can only be members of Processgroups, not Nodegroups!\n")
                is_valid = false 
            end
        end
    end
    error_log["is_valid"] = is_valid
end

function validate_gen_constraints(error_log::OrderedDict, input_data::Predicer.InputData)
    is_valid = error_log["is_valid"]
    gcs = input_data.gen_constraints
    nodes = input_data.nodes
    processes = input_data.processes

    for gc in collect(keys(gcs))
        # Check that the given operators are valid.
        if !(gcs[gc].type in ["gt", "eq", "st"])
            push!(error_log["errors"], "The operator '" * gcs[gc].type * "' is not valid for the gen_constraint '" * gc *"'.\n")
            is_valid = false 
        end

        #check that the factors of the same gc are all of the same type
        if length(unique(map(f -> f.var_type, gcs[gc].factors))) > 1
            push!(error_log["errors"], "A gen_constraint (" * gc * ") cannot have factors of different types.\n")
            is_valid = false 
        end

        # Check that gen_constraint has at least one factor. 
        if isempty(gcs[gc].factors)
            push!(error_log["errors"], "The gen_constraint (" * gc * ") must have at least one series for a 'factor' defined.\n")
            is_valid = false 
        else
            for fac in gcs[gc].factors
                if fac.var_type == "state"
                    #check that the linked node exists
                    if !(fac.var_tuple[1] in collect(keys(nodes)))
                        push!(error_log["errors"], "The node '"* fac.var_tuple[1] * "' linked to gen_constraint (" * gc * ") is not a node.\n")
                        is_valid = false 
                    else
                        # check that the linked node has a state
                        if !nodes[fac.var_tuple[1]].is_state
                            push!(error_log["errors"], "The node '"* fac.var_tuple[1] * "' linked to gen_constraint (" * gc * ") has no state variable.\n")
                            is_valid = false 
                        end
                    end
                elseif fac.var_type == "online"
                    #check that the linked process exists
                    if !(fac.var_tuple[1] in collect(keys(processes)))
                        push!(error_log["errors"], "The process '"* fac.var_tuple[1] * "' linked to gen_constraint (" * gc * ") is not a process.\n")
                        is_valid = false 
                    else
                        # check that the linked process has a state
                        if !processes[fac.var_tuple[1]].is_online
                            push!(error_log["errors"], "The process '"* fac.var_tuple[1] * "' linked to gen_constraint (" * gc * ") has no online functionality.\n")
                            is_valid = false 
                        end
                    end
                elseif fac.var_type == "flow"
                    #check that the linked process exists
                    if !(fac.var_tuple[1] in collect(keys(processes)))
                        push!(error_log["errors"], "The process '"* fac.var_tuple[1] * "' linked to gen_constraint (" * gc * ") is not a process.\n")
                        is_valid = false 
                    else
                        # check that the linked process has a relevant topo
                        p = fac.var_tuple[1]
                        c = fac.var_tuple[2]
                        if length(filter(t -> t.source == c || t.sink == c, processes[fac.var_tuple[1]].topos)) < 1
                            push!(error_log["errors"], "The flow ("* p * ", " * c * ") linked to gen_constraint (" * gc * ") could not be found.\n")
                            is_valid = false 
                        end
                    end
                end
            end
        end

        # Check that setpoints have no constants, and non-setpoints have constants. 
        if gcs[gc].is_setpoint
            if !isempty(gcs[gc].constant)
                push!(error_log["errors"], "The gen_constraint (" * gc * ") of the 'setpoint' can not have a series for a 'constant'.\n")
                is_valid = false 
            end
        else
            if isempty(gcs[gc].constant)
                push!(error_log["errors"], "The gen_constraint (" * gc * ") of the 'normal' type must have a series for a 'constant'.\n")
                is_valid = false 
            end
        end
    end

    error_log["is_valid"] = is_valid
end

"""
    function validate_processes(error_log::OrderedDict, input_data::Predicer.InputData)

Checks that each Process is valid, for example a cf process cannot be part of a reserve. 
"""
function validate_processes(error_log::OrderedDict, input_data::Predicer.InputData)
    is_valid = error_log["is_valid"]
    processes = input_data.processes
    for pname in keys(processes)

        # conversion and rest match
        # eff < 0
        # !(is_cf && is_res)
        # !(is_cf && is_online)
        # 0 <= min_load <= 1
        # 0 <= max_load <= 1
        # min load <= max_load
        # min_offline >= 0
        # min_online >= 0

        p = processes[pname]
        if 0 > p.eff && p.conversion != 3
            push!(error_log["errors"], "Invalid Process: ", p.name, ". The efficiency of a Process cannot be negative. .\n")
            is_valid = false
        end
        if !(0 <= p.load_min <= 1)
            push!(error_log["errors"], "Invalid Process: ", p.name, ". The min load of a process must be between 0 and 1.\n")
            is_valid = false 
        end
        if !(0 <= p.load_max <= 1)
            push!(error_log["errors"], "Invalid Process: ", p.name, ". The max load of a process must be between 0 and 1.\n")
            is_valid = false 
        end
        if p.load_min > p.load_max
            push!(error_log["errors"], "Invalid Process: ", p.name, ". The min load of a process must be less or equal to the max load.\n")
            is_valid = false 
        end
        if p.min_online < 0
            push!(error_log["errors"], "Invalid Process: ", p.name, ". The min online time of a process must be more or equal to 0.\n")
            is_valid = false 
        end
        if p.min_online < 0
            push!(error_log["errors"], "Invalid Process: ", p.name, ". The min offline time of a process must be more or equal to 0.\n")
            is_valid = false 
        end

        if p.is_cf
            if p.is_res
                push!(error_log["errors"], "Invalid Process: ", p.name, ". A cf process cannot be part of a reserve.\n")
                is_valid = false 
            end
            if p.is_online
                push!(error_log["errors"], "Invalid Process: ", p.name, ". A cf process cannot have online functionality.\n")
                is_valid = false 
            end
            validate_timeseriesdata(error_log, p.cf, input_data.temporals.ts_format)
        end

        if !isempty(p.eff_ts)
            validate_timeseriesdata(error_log, p.eff_ts, input_data.temporals.ts_format)
        end
    end
    error_log["is_valid"] = is_valid
end


"""
    function validate_nodes(error_log::OrderedDict, input_data::Predicer.InputData)

Checks that each Node is valid, for example a commodity node cannot have a state or an inflow. 
"""
function validate_nodes(error_log::OrderedDict, input_data::Predicer.InputData)
    is_valid = error_log["is_valid"]
    nodes = input_data.nodes
    for nname in keys(nodes)
        n = nodes[nname]
        if n.is_market && n.is_commodity
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A commodity Node cannot be a market.\n")
            is_valid = false
        end
        if n.is_state && n.is_commodity
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A commodity Node cannot have a state.\n")
            is_valid = false
        end
        if n.is_res && n.is_commodity
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A commodity Node cannot be part of a reserve.\n")
            is_valid = false
        end
        if n.is_inflow && n.is_commodity
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A commodity Node cannot have an inflow.\n")
            is_valid = false
        end
        if n.is_market && n.is_inflow
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A market node cannot have an inflow.\n")
            is_valid = false
        end
        if n.is_market && n.is_state
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A market node cannot have a state.\n")
            is_valid = false
        end
        if n.is_market && n.is_res
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A market node cannot have a reserve.\n")
            is_valid = false
        end
        if isempty(n.cost) && n.is_commodity
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A commodity Node must have a price.\n")
            is_valid = false
        else
            validate_timeseriesdata(error_log, n.cost, input_data.temporals.ts_format)
        end
        if isempty(n.inflow) && n.is_inflow
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A Node with inflow must have an inflow timeseries.\n")
            is_valid = false        
        else
            validate_timeseriesdata(error_log, n.inflow, input_data.temporals.ts_format)
        end
        if n.is_state
            if isnothing(n.state)
                push!(error_log["errors"], "Invalid Node: ", n.name, ". A Node defined as having a state must have a State.\n")
                is_valid = false
            else
                validate_state(error_log, n.state)
            end
        end
    end
    error_log["is_valid"] = is_valid
end


"""
    function validate_state(error_log::OrderedDict, s::Predicer.State)

Checks that the values of a state are valid and logical.
"""
function validate_state(error_log::OrderedDict, s::Predicer.State)
    is_valid = error_log["is_valid"]
    if s.out_max < 0
        push!(error_log["errors"], "Invalid state parameters. Maximum outflow to a state cannot be smaller than 0.\n")
        is_valid = false
    end
    if s.in_max < 0
        push!(error_log["errors"], "Invalid state parameters. Maximum inflow to a state cannot be smaller than 0.\n")
        is_valid = false
    end
    if s.state_max < 0
        push!(error_log["errors"], "Invalid state parameters. State max cannot be smaller than 0.\n")
        is_valid = false
    end
    if s.state_max < 0
        push!(error_log["errors"], "Invalid state parameters. State max cannot be smaller than 0.\n")
        is_valid = false
    end
    if s.state_max < s.state_min
        push!(error_log["errors"], "Invalid state parameters. State max cannot be smaller than state min.\n")
        is_valid = false
    end
    if !(s.state_min <= s.initial_state <= s.state_max)
        push!(error_log["errors"], "Invalid state parameters. The initial state has to be between state min and state max.\n")
        is_valid = false
    end
    error_log["is_valid"] = is_valid
end


"""
    function validate_timeseriesdata(error_log::OrderedDict, tsd::TimeSeriesData, ts_format::String)

Checks that the TimeSeriesData struct has one timeseries per scenario, and that the timesteps are in chronological order.
"""
function validate_timeseriesdata(error_log::OrderedDict, tsd::Predicer.TimeSeriesData, ts_format::String)
    is_valid = error_log["is_valid"]
    scenarios = map(x -> x.scenario, tsd.ts_data)
    if scenarios != unique(scenarios)
        push!(error_log["errors"], "Invalid timeseries data. Multiple timeseries for the same scenario.\n")
        is_valid = false
    else
        for s in scenarios
            ts = tsd(s)
            for i in 1:length(ts)-1
                if ZonedDateTime(ts[i+1][1], ts_format) - ZonedDateTime(ts[i][1], ts_format) <= Dates.Minute(0)
                    push!(error_log["errors"], "Invalid timeseries. Timesteps not in chronological order.\n")
                    is_valid = false
                end
            end
        end
    end
    error_log["is_valid"] = is_valid
end


"""
    validate_temporals(error_log::OrderedDict, input_data::Predicer.InputData)

Checks that the time data in the model is valid. 
"""
function validate_temporals(error_log::OrderedDict, input_data::Predicer.InputData)
    is_valid = error_log["is_valid"]
    temporals = input_data.temporals
    for i in 1:length(temporals.t)-1
        if ZonedDateTime(temporals.t[i+1], temporals.ts_format) - ZonedDateTime(temporals.t[i], temporals.ts_format) <= Dates.Minute(0)
            push!(error_log["errors"], "Invalid timeseries. Timesteps not in chronological order.\n")
            is_valid = false
        end
    end
    error_log["is_valid"] = is_valid
end


"""
    validate_unique_names(error_log::OrderedDict, input_data::Predicer.InputData)

Checks that the entity names in the input data are unique.
"""
function validate_unique_names(error_log::OrderedDict, input_data::Predicer.InputData)
    is_valid = error_log["is_valid"]
    p_names = collect(keys(input_data.processes))
    n_names = collect(keys(input_data.nodes))
    if length(p_names) != length(unique(p_names))
        push!(error_log["errors"], "Invaling naming. Two processes cannot have the same name.\n")
        is_valid = false
    end
    if length(n_names) != length(unique(n_names))
        push!(error_log["errors"], "Invaling naming. Two nodes cannot have the same name.\n")
        is_valid = false
    end
    if length([p_names; n_names]) != length(unique([p_names; n_names]))
        push!(error_log["errors"], "Invaling naming. A process and a node cannot have the same name.\n")
        is_valid = false
    end
    error_log["is_valid"] = is_valid
end 


"""
    function validate_process_topologies(error_log::OrderedDict, input_data::Predicer.InputData)

Checks that the topologies in the input data are valid. 
"""
function validate_process_topologies(error_log::OrderedDict, input_data::Predicer.InputData)
    processes = input_data.processes
    nodes = input_data.nodes
    is_valid = error_log["is_valid"]
    
    for p in keys(processes)
        topos = processes[p].topos
        sources = filter(t -> t.sink == p, topos)
        sinks = filter(t -> t.source == p, topos)
        other = filter(t -> !(t in sources) && !(t in sinks), topos)
        for topo in sinks
            if topo.sink in keys(nodes)
                if nodes[topo.sink].is_commodity
                    push!(error_log["errors"], "Invalid topology: Process " * p * ". A commodity node cannot be a sink.\n")
                    is_valid = false
                end
                if processes[p].conversion != 3 && nodes[topo.sink].is_market
                    push!(error_log["errors"], "Invalid topology: Process " * p * ". A process with conversion != 3 cannot have a market as a sink.\n")
                    is_valid = false
                end
            else
                push!(error_log["errors"], "Invalid topology: Process " * p * ". Process sink not found in nodes.\n")
                is_valid = false
            end
        end
        for topo in sources
            if topo.source in keys(nodes)
                if processes[topo.sink].is_cf
                    push!(error_log["errors"], "Invalid topology: Process " * p * ". A CF process can not have a source.\n")
                    is_valid = false
                end
                if nodes[topo.source].is_market
                    push!(error_log["errors"], "Invalid topology: Process " * p * ". A process cannot have a market as a source.\n")
                    is_valid = false
                end
            else
                push!(error_log["errors"], "Invalid topology: Process " * p * ". Process source not found in nodes.\n")
                is_valid = false
            end
        end
        if processes[p].conversion == 2
            if length(processes[p].topos) > 1
                push!(error_log["errors"], "Invalid topology: Process " * p * ". A transport process cannot have several branches.\n")
                is_valid = false
            end
            if length(sources) > 0 || length(sinks) > 0
                push!(error_log["errors"], "Invalid topology: Process " * p * ". A transport process cannot have itself as a source or sink.\n")
                is_valid = false
            end
        elseif processes[p].conversion == 1
            if !(p in map(x -> x.sink, sources) || p in map(x -> x.source, sinks))
                push!(error_log["errors"], "Invalid topology: Process " * p * ". A process with conversion 1 must have itself as a source or a sink.\n")
                is_valid = false
            end
        end
    end
    error_log["is_valid"] = is_valid
end


function validate_data(input_data)
    error_log = OrderedDict()
    error_log["is_valid"] = true
    error_log["errors"] = []
    # Call functions validating data
    validate_process_topologies(error_log, input_data)
    validate_processes(error_log, input_data)
    validate_nodes(error_log, input_data)
    validate_temporals(error_log, input_data)
    validate_unique_names(error_log, input_data)
    validate_gen_constraints(error_log, input_data)
    validate_inflow_blocks(error_log, input_data)
    validate_groups(error_log, input_data)
    # Return log. 
    return error_log
end