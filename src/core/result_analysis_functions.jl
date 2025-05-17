function compute_hourly_costs_stochastic_multistep_simulations_check(grid,result,start_hour_simulation,end_hour_simulation,vector)
    for hour in start_hour_simulation:end_hour_simulation
        hourly_cost_hour = 0
        nw = hour - start_hour_simulation + 1
        for (g_id,g) in grid["gen"]
            hourly_cost_hour += result["solution"]["nw"]["$nw"]["gen"][g_id]["pg"]*g["cost"][1]*100
        end
        push!(vector,hourly_cost_hour)
    end
end

function compute_hourly_costs_stochastic_multistep_simulations_check_hourly(grid,result,start_hour_simulation,end_hour_simulation,vector)
    for hour in start_hour_simulation:end_hour_simulation
        hourly_cost_hour = 0
        nw = hour - start_hour_simulation + 1
        for (g_id,g) in grid["gen"]
            hourly_cost_hour += result["$nw"]["solution"]["nw"]["$nw"]["gen"][g_id]["pg"]*g["cost"][1]*100
        end
        push!(vector,hourly_cost_hour)
    end
end

function prepare_AC_feasibility_check_stochastic_multistep_hourly(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict, input_base, n_hours)
    orig_buses = maximum(parse.(Int, keys(input_base["bus"])))
    println("Number of original buses is $orig_buses")
    for t in 1:n_hours
        println("t is $(t)")
        for (sw_id,sw) in input_dict["nw"]["$t"]["switch"]
            if !haskey(sw,"auxiliary")
                println("SWITCH $sw_id, BUS $(sw["t_bus"])")
                if result_dict["$t"]["solution"]["nw"]["$t"]["switch"][sw_id]["status"] >= 0.9
                    println("Switch $sw_id is closed, Connecting everything back, no busbar splitting on bus $(sw["bus_split"])")
                    #delete!(input_ac_check["bus"],"$(input_ac_check["switch"][sw_id]["t_bus"])")
                    for l in keys(switch_couples)
                        if switch_couples[l]["bus_split"] == sw["bus_split"]
                            println("SWITCH COUPLE IS $l")
                            #println("Starting from switch $(switch_couples[l]["f_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["t_bus"])")
                            #println("Then switch $(switch_couples[l]["t_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["t_bus"])")
                            if input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                println("WE GO WITH SWITCH $(switch_couples[l]["f_sw"])")
                                aux =  deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["auxiliary"])
                                orig = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["original"])
                                if aux == "gen"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"])
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "load"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"])
                                    input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "convdc"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"])
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "branch"                
                                    if input_dict["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    elseif input_dict["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    end
                                end
                            elseif input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                println("WE GO WITH SWITCH $(switch_couples[l]["t_sw"])")
                                println("----------------------------")
                                aux =  deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["auxiliary"])
                                orig = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["original"])
                                if aux == "gen"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"])
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "load"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"])
                                    input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "convdc"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"])
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "branch"                
                                    if input_dict["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    elseif input_dict["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    end
                                end
                            end
                        end
                    end
                elseif result_dict["$t"]["solution"]["nw"]["$t"]["switch"][sw_id]["status"] <= 0.1
                    println("Switch $sw_id is open, busbar splitting on bus $(sw["bus_split"])")
                    delete!(input_ac_check["nw"]["$t"]["switch"],sw_id)
                    for l in keys(switch_couples)
                        if switch_couples[l]["bus_split"] == sw["bus_split"]
                            println("SWITCH COUPLE IS $l")
                            #println("Starting from switch $(switch_couples[l]["f_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["t_bus"])")
                            #println("Then switch $(switch_couples[l]["t_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["t_bus"])")
                            if result_dict["$t"]["solution"]["nw"]["$t"]["switch"]["$(switch_couples["$l"]["switch_split"])"]["status"] >= 0.9
                                aux =  deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["auxiliary"])
                                orig = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["original"])
                                if aux == "gen"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"])
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "load"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"])
                                    input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "convdc"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"])
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "branch"                
                                    if input_dict["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    elseif input_dict["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    end
                                end
                            elseif result_dict["$t"]["solution"]["nw"]["$t"]["switch"]["$(switch_couples["$l"]["switch_split"])"]["status"] <= 0.1
                                switch_t = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]) 
                                aux_t = switch_t["auxiliary"]
                                orig_t = switch_t["original"]
                                print([l,aux_t,orig_t],"\n")
                                if result_dict["$t"]["solution"]["nw"]["$t"]["switch"]["$(switch_t["index"])"]["status"] <= 0.1
                                    delete!(input_ac_check["nw"]["$t"]["switch"],"$(switch_t["index"])")
                                elseif result_dict["$t"]["solution"]["nw"]["$t"]["switch"]["$(switch_t["index"])"]["status"] >= 0.9
                                    if aux_t == "gen"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"])
                                        input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"]],"\n")
                                    elseif aux_t == "load"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"])
                                        input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"]],"\n")
                                    elseif aux_t == "convdc"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"])
                                        input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"]],"\n")
                                    elseif aux_t == "branch" 
                                        if input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"]],"\n")
                                        elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"]],"\n")
                                        end
                                    end
                                end
                            
                                switch_f = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]) 
                                aux_f = switch_f["auxiliary"]
                                orig_f = switch_f["original"]
                                print([l,aux_f,orig_f],"\n")
                                if result_dict["$t"]["solution"]["nw"]["$t"]["switch"]["$(switch_f["index"])"]["status"] <= 0.1
                                    delete!(input_ac_check["nw"]["$t"]["switch"],"$(switch_t["index"])")
                                else
                                    if aux_f == "gen"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"])
                                        input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"]],"\n")
                                    elseif aux_f == "load"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"])
                                        input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"]],"\n")
                                    elseif aux_f == "convdc"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"])
                                        input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"]],"\n")
                                    elseif aux_f == "branch"
                                        if input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_ac_check["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"]],"\n")
                                        elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_ac_check["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"]],"\n")
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        input_ac_check["nw"]["$t"]["switch"] = Dict{String,Any}()
        input_ac_check["nw"]["$t"]["switch_couples"] = Dict{String,Any}()
    end
end

function prepare_AC_feasibility_check_stochastic_multistep(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict, input_base, n_hours, n_scenarios)
    orig_buses = maximum(parse.(Int, keys(input_base["bus"])))
    println("Number of original buses is $orig_buses")
    for t in 1:(n_hours*n_scenarios)
        println("t is $(t)")
        for (sw_id,sw) in input_dict["nw"]["$t"]["switch"]
            if !haskey(sw,"auxiliary")
                println("SWITCH $sw_id, BUS $(sw["t_bus"])")
                if result_dict["solution"]["nw"]["$t"]["switch"][sw_id]["status"] >= 0.9
                    println("Switch $sw_id is closed, Connecting everything back, no busbar splitting on bus $(sw["bus_split"])")
                    #delete!(input_ac_check["bus"],"$(input_ac_check["switch"][sw_id]["t_bus"])")
                    for l in keys(switch_couples)
                        if switch_couples[l]["bus_split"] == sw["bus_split"]
                            println("SWITCH COUPLE IS $l")
                            #println("Starting from switch $(switch_couples[l]["f_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["t_bus"])")
                            #println("Then switch $(switch_couples[l]["t_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["t_bus"])")
                            if input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                println("WE GO WITH SWITCH $(switch_couples[l]["f_sw"])")
                                aux =  deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["auxiliary"])
                                orig = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["original"])
                                if aux == "gen"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"])
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "load"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"])
                                    input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "convdc"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"])
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "branch"                
                                    if input_dict["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    elseif input_dict["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    end
                                end
                            elseif input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                println("WE GO WITH SWITCH $(switch_couples[l]["t_sw"])")
                                println("----------------------------")
                                aux =  deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["auxiliary"])
                                orig = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["original"])
                                if aux == "gen"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"])
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "load"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"])
                                    input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "convdc"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"])
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "branch"                
                                    if input_dict["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    elseif input_dict["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    end
                                end
                            end
                        end
                    end
                elseif result_dict["solution"]["nw"]["$t"]["switch"][sw_id]["status"] <= 0.1
                    println("Switch $sw_id is open, busbar splitting on bus $(sw["bus_split"])")
                    delete!(input_ac_check["nw"]["$t"]["switch"],sw_id)
                    for l in keys(switch_couples)
                        if switch_couples[l]["bus_split"] == sw["bus_split"]
                            println("SWITCH COUPLE IS $l")
                            #println("Starting from switch $(switch_couples[l]["f_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["t_bus"])")
                            #println("Then switch $(switch_couples[l]["t_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["t_bus"])")
                            if result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_couples["$l"]["switch_split"])"]["status"] >= 0.9
                                aux =  deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["auxiliary"])
                                orig = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["original"])
                                if aux == "gen"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"])
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "load"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"])
                                    input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "convdc"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"])
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "branch"                
                                    if input_dict["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    elseif input_dict["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    end
                                end
                            elseif result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_couples["$l"]["switch_split"])"]["status"] <= 0.1
                                switch_t = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]) 
                                aux_t = switch_t["auxiliary"]
                                orig_t = switch_t["original"]
                                print([l,aux_t,orig_t],"\n")
                                if result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_t["index"])"]["status"] <= 0.1
                                    delete!(input_ac_check["nw"]["$t"]["switch"],"$(switch_t["index"])")
                                elseif result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_t["index"])"]["status"] >= 0.9
                                    if aux_t == "gen"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"])
                                        input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"]],"\n")
                                    elseif aux_t == "load"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"])
                                        input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"]],"\n")
                                    elseif aux_t == "convdc"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"])
                                        input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"]],"\n")
                                    elseif aux_t == "branch" 
                                        if input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"]],"\n")
                                        elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"]],"\n")
                                        end
                                    end
                                end
                            
                                switch_f = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]) 
                                aux_f = switch_f["auxiliary"]
                                orig_f = switch_f["original"]
                                print([l,aux_f,orig_f],"\n")
                                if result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_f["index"])"]["status"] <= 0.1
                                    delete!(input_ac_check["nw"]["$t"]["switch"],"$(switch_t["index"])")
                                else
                                    if aux_f == "gen"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"])
                                        input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"]],"\n")
                                    elseif aux_f == "load"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"])
                                        input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"]],"\n")
                                    elseif aux_f == "convdc"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"])
                                        input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"]],"\n")
                                    elseif aux_f == "branch"
                                        if input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_ac_check["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"]],"\n")
                                        elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_ac_check["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"]],"\n")
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        input_ac_check["nw"]["$t"]["switch"] = Dict{String,Any}()
        input_ac_check["nw"]["$t"]["switch_couples"] = Dict{String,Any}()
    end
end

function compute_gen_capacity(data,results,start_hour,end_hour,dict)
    gen_type = []
    for (g_id,g) in data["gen"]
        push!(gen_type,g["type"])
    end
    types = unique(gen_type)

    for t in types
        dict["$t"] = 0
    end
    for hour in start_hour:end_hour
        if haskey(results,"$hour")
            for t in types
                for (g_id,g) in data["gen"]
                    if g["type"] == t
                        dict["$t"] += results["$hour"]["solution"]["gen"][g_id]["pg"]
                    end
                end
            end
        end
    end
end

function compute_gen_capacity_OPF(data,results,start_hour,end_hour,dict)
    gen_type = []
    for (g_id,g) in data["gen"]
        push!(gen_type,g["type"])
    end
    types = unique(gen_type)

    for hour in start_hour:end_hour
        if haskey(results["solution"]["nw"],"$hour")
            dict["$hour"] = Dict{String,Any}()
            for t in types
                dict["$hour"]["$t"] = 0
            end
            for t in types
                for (g_id,g) in data["gen"]
                    if g["type"] == t
                        dict["$hour"]["$t"] += results["solution"]["nw"]["$hour"]["gen"][g_id]["pg"]
                    end
                end
            end
        end
    end
end

function compute_gen_capacity_hourly(data,results,start_hour,end_hour,dict)
    gen_type = []
    for (g_id,g) in data["gen"]
        push!(gen_type,g["type"])
    end
    types = unique(gen_type)


    for hour in start_hour:end_hour
        if haskey(results,"$hour")
            dict["$hour"] = Dict{String,Any}()
            for t in types
                dict["$hour"]["$t"] = 0
            end
            for t in types
                for (g_id,g) in data["gen"]
                    if g["type"] == t
                        dict["$hour"]["$t"] += results["$hour"]["solution"]["nw"]["$hour"]["gen"][g_id]["pg"]
                    end
                end
            end
        end
    end
end

function compute_gen_capacity_OPF_zone(data,results,start_hour,end_hour,zones,dict)
    for zone in zones
        dict["$zone"] = Dict{String,Any}()
        gen_type = []
        for (g_id,g) in data["gen"]
            push!(gen_type,g["type"])
        end
        types = unique(gen_type)

        for hour in start_hour:end_hour
            dict["$zone"]["$hour"] = Dict{String,Any}()
            if haskey(results["solution"]["nw"],"$hour")
                for t in types
                    dict["$zone"]["$hour"]["$t"] = 0
                    for (g_id,g) in data["gen"]
                        if g["zone"] == zone && g["type"] == t
                            dict["$zone"]["$hour"]["$t"] += results["solution"]["nw"]["$hour"]["gen"][g_id]["pg"]
                        end
                    end
                end
            end
        end
    end
end

function compute_gen_capacity_hourly_zone(data,results,start_hour,end_hour,zones,dict)
    for zone in zones
        dict["$zone"] = Dict{String,Any}()
        gen_type = []
        for (g_id,g) in data["gen"]
            push!(gen_type,g["type"])
        end
        types = unique(gen_type)

        for hour in start_hour:end_hour
            dict["$zone"]["$hour"] = Dict{String,Any}()
            if haskey(results,"$hour")
                dict["$zone"]["$hour"] = Dict{String,Any}()
                for t in types
                    dict["$zone"]["$hour"]["$t"] = 0
                    for (g_id,g) in data["gen"]
                        if g["zone"] == zone && g["type"] == t
                            dict["$zone"]["$hour"]["$t"] += results["$hour"]["solution"]["nw"]["$hour"]["gen"][g_id]["pg"]
                        end
                    end
                end
            end
        end
    end
end


function print_switch_results(test_case,original_test_case,results)
    for sw_id in 1:length(test_case["switch"])
        if haskey(test_case["switch"]["$(sw_id)"],"auxiliary")
            println("Switch $sw_id, aux is $(test_case["switch"]["$(sw_id)"]["auxiliary"]), orig is $(test_case["switch"]["$(sw_id)"]["original"]), t_bus is $(test_case["switch"]["$(sw_id)"]["t_bus"]), $(results["solution"]["switch"]["$sw_id"]["status"]), bus_split is $(test_case["switch"]["$(sw_id)"]["bus_split"])")    
            if test_case["switch"]["$(sw_id)"]["auxiliary"] == "branch"
                println("      Branch $(test_case["switch"]["$(sw_id)"]["original"]), f_bus $(original_test_case["branch"]["$(test_case["switch"]["$(sw_id)"]["original"])"]["f_bus"]), t_bus $(original_test_case["branch"]["$(test_case["switch"]["$(sw_id)"]["original"])"]["t_bus"])")
            end
        else
            println("Switch $sw_id,  is $(results["solution"]["switch"]["$sw_id"]["status"]), bus_split is $(test_case["switch"]["$(sw_id)"]["bus_split"])")
        end
    end
end