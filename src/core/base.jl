function add_ZIL_stochastic_multitemporal_constraints!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})
    for (n, nw_ref) in ref[:it][:pm][:nw]
        if haskey(nw_ref, :dcswitch)
            nw_ref[:ZIL_dc_switches] = []
            if nw_ref[:scenario] == 1
                for (i,switch) in nw_ref[:dcswitch] 
                    if !haskey(switch, "auxiliary")
                        push!(dc_ZIL,(i,nw))
                    end
                end
            end
        end 

        bus_arcs_to = Dict([(bus["bus_i"], []) for (i,bus) in nw_ref[:bus]])
        for (l,i,j) in nw_ref[:arcs_to]
            push!(bus_arcs_to[i], (l,i,j))
        end
        nw_ref[:bus_arcs_to] = bus_arcs_to

        if haskey(nw_ref,:dcswitch) # adding dc switches
            nw_ref[:arcs_from_sw_dc] = [(i,switch["f_busdc"],switch["t_busdc"]) for (i,switch) in nw_ref[:dcswitch]]
            nw_ref[:arcs_to_sw_dc]   = [(i,switch["t_busdc"],switch["f_busdc"]) for (i,switch) in nw_ref[:dcswitch]]
            nw_ref[:arcs_sw_dc] = [nw_ref[:arcs_from_sw_dc]; nw_ref[:arcs_to_sw_dc]]

            bus_arcs_sw_dc = Dict((i, Tuple{Int,Int,Int}[]) for (i,bus) in nw_ref[:busdc])
            for (l,i,j) in nw_ref[:arcs_sw_dc]
                push!(bus_arcs_sw_dc[i], (l,i,j))
            end
            nw_ref[:bus_arcs_sw_dc] = bus_arcs_sw_dc
        else 
            nw_ref[:dcswitch] = Dict{String, Any}()
            nw_ref[:arcs_from_sw_dc] = Dict{String, Any}()
            nw_ref[:arcs_to_sw_dc]   = Dict{String, Any}()
            nw_ref[:arcs_sw_dc] = Dict{String, Any}()
        end 

        if haskey(nw_ref, :convdc)
            #Filter converters & DC branches with status 0 as well as wrong bus numbers
            nw_ref[:convdc] = Dict([x for x in nw_ref[:convdc] if (x.second["status"] == 1 && x.second["busdc_i"] in keys(nw_ref[:busdc]) && x.second["busac_i"] in keys(nw_ref[:bus]))])

            nw_ref[:arcs_conv_acdc] = [(i,conv["busac_i"],conv["busdc_i"]) for (i,conv) in nw_ref[:convdc]]

            # Bus converters for existing ac buses
            bus_convs_ac = Dict([(i, []) for (i,bus) in nw_ref[:bus]])
            nw_ref[:bus_convs_ac] = _PMACDC.assign_bus_converters!(nw_ref[:convdc], bus_convs_ac, "busac_i")    

            # Bus converters for existing ac buses
            bus_convs_dc = Dict([(bus["busdc_i"], []) for (i,bus) in nw_ref[:busdc]])
            nw_ref[:bus_convs_dc]= _PMACDC.assign_bus_converters!(nw_ref[:convdc], bus_convs_dc, "busdc_i") 

            # Add DC reference buses
            ref_buses_dc = Dict{String, Any}()
            for (k,v) in nw_ref[:convdc]
                if v["type_dc"] == 2
                    ref_buses_dc["$k"] = v
                end
            end

            if length(ref_buses_dc) == 0
                for (k,v) in nw_ref[:convdc]
                    if v["type_ac"] == 2
                        ref_buses_dc["$k"] = v
                    end
                end
                Memento.warn(_PM._LOGGER, "no reference DC bus found, setting reference bus based on AC bus type")
            end

            for (k,conv) in nw_ref[:convdc]
                conv_id = conv["index"]
                if conv["type_ac"] == 2 && conv["type_dc"] == 1
                    Memento.warn(_PM._LOGGER, "For converter $conv_id is chosen P is fixed on AC and DC side. This can lead to infeasibility in the PF problem.")
                elseif conv["type_ac"] == 1 && conv["type_dc"] == 1
                    Memento.warn(_PM._LOGGER, "For converter $conv_id is chosen P is fixed on AC and DC side. This can lead to infeasibility in the PF problem.")
                end
                convbus_ac = conv["busac_i"]
                if conv["Vmmax"] < nw_ref[:bus][convbus_ac]["vmin"]
                    Memento.warn(_PM._LOGGER, "The maximum AC side voltage of converter $conv_id is smaller than the minimum AC bus voltage")
                end
                if conv["Vmmin"] > nw_ref[:bus][convbus_ac]["vmax"]
                    Memento.warn(_PM._LOGGER, "The miximum AC side voltage of converter $conv_id is larger than the maximum AC bus voltage")
                end
            end

            if length(ref_buses_dc) > 1
                ref_buses_warn = ""
                for (rb) in keys(ref_buses_dc)
                    ref_buses_warn = ref_buses_warn*rb*", "
                end
                Memento.warn(_PM._LOGGER, "multiple reference buses found, i.e. "*ref_buses_warn*"this can cause infeasibility if they are in the same connected component")
            end
            nw_ref[:ref_buses_dc] = ref_buses_dc
            nw_ref[:buspairsdc] = _PMACDC.buspair_parameters_dc(nw_ref[:arcs_dcgrid_from], nw_ref[:branchdc], nw_ref[:busdc])
        else
            nw_ref[:convdc] = Dict{String, Any}()
            nw_ref[:busdc] = Dict{String, Any}()
            nw_ref[:bus_convs_dc] = Dict{String, Any}()
            nw_ref[:ref_buses_dc] = Dict{String, Any}()
            nw_ref[:buspairsdc] = Dict{String, Any}()
            # Bus converters for existing ac buses
            bus_convs_ac = Dict([(i, []) for (i,bus) in nw_ref[:bus]])
            nw_ref[:bus_convs_ac] = _PMACDC.assign_bus_converters!(nw_ref[:convdc], bus_convs_ac, "busac_i")    
        end

        if haskey(nw_ref,:switch) # adding ac switches
            print("switch","\n")
            nw_ref[:arcs_from_sw] = [(i,switch["f_bus"],switch["t_bus"]) for (i,switch) in nw_ref[:switch]]
            nw_ref[:arcs_to_sw]   = [(i,switch["t_bus"],switch["f_bus"]) for (i,switch) in nw_ref[:switch]]
            nw_ref[:arcs_sw] = [nw_ref[:arcs_from_sw]; nw_ref[:arcs_to_sw]]
        end
    end

    hours = ref[:it][:pm][:hours]
    scenarios = ref[:it][:pm][:scenarios]
    
    scenario_idx = 1 # calling the first scenario
    first_hours = []
    for hour in 1:hours
        push!(first_hours,(hour - 1)*scenarios + scenario_idx)
    end
    ac_ZIL = []
    for hour in first_hours
        if haskey(ref[:it][:pm][:nw][hour],:switch)
            for (sw_id,sw) in ref[:it][:pm][:nw][hour][:switch]
                if !haskey(sw, "auxiliary")
                    push!(ac_ZIL,(sw_id,hour))
                end
            end
        end
    end
    ref[:it][:pm][:ac_ZIL] = ac_ZIL
    println(ac_ZIL)
end
