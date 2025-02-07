function pf_through_branch(result,grid,branch_number,vector,start_hour,end_hour)
    for hour in start_hour:end_hour
        push!(vector,result["$hour"]["solution"]["branch"]["$(branch_number)"]["pf"])
    end
end

function pf_through_branchdc(result,grid,branch_number,vector,start_hour,end_hour)
    for hour in start_hour:end_hour
        push!(vector,result["$hour"]["solution"]["branchdc"]["$(branch_number)"]["pf"])
    end
end


function compute_electricity_prices(grid,results,start_hour,end_hour,zones,load_series)
    electricity_prices = Dict{String,Any}()
    for zone in zones
        electricity_prices["$zone"] = Dict{String,Any}()
        electricity_prices["$zone"]["hourly_price"] = [] 
        electricity_prices["$zone"]["avg_price"] = 0
        for hour in start_hour:end_hour
            if haskey(results,"$hour")
                gen_costs = 0
                for (g_id,g) in grid["gen"]
                    if g["zone"] == zone
                        #gen_costs = gen_costs + results["$hour"]["solution"]["gen"][g_id]["pg"]*grid["gen"][g_id]["cost"][1]
                        gen_costs = gen_costs + results["$hour"]["solution"]["gen"][g_id]["pg_cost"]
                    end
                end
                el_price = (gen_costs*10^2)/(load_series[zone]["pu"][hour]*10^2)
                push!(electricity_prices["$zone"]["hourly_price"],el_price)
            end
        end
        electricity_prices["$zone"]["avg_price"] = sum(electricity_prices["$zone"]["hourly_price"])/(length(start_hour:end_hour)) #€/MWh
    end
    return electricity_prices
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

function compute_gen_capacity_zone(data,results,start_hour,end_hour,zones)
    gen_per_zone = Dict{String,Any}()
    for zone in zones
        gen_per_zone["$zone"] = Dict{String,Any}()
        gen_type = []
        for (g_id,g) in data["gen"]
            push!(gen_type,g["type"])
        end
        types = unique(gen_type)

        for t in types
            gen_per_zone["$zone"]["$t"] = 0
        end
        for hour in start_hour:end_hour
            if haskey(results,"$hour")
                for t in types
                    for (g_id,g) in data["gen"]
                        if g["zone"] == zone && g["type"] == t
                            gen_per_zone["$zone"]["$t"] += results["$hour"]["solution"]["gen"][g_id]["pg"]
                        end
                    end
                end
            end
        end
    end
    return gen_per_zone
end

function compute_vas(dict,grid,results,hour)
    #dict = Dict{Stri}()
    for (b_id,b) in grid["bus"]
        if b["bus_type"] != 3 && results[hour]["solution"]["bus"]["$b_id"]["va"] != 0.0
            dict["$b_id"] = results[hour]["solution"]["bus"]["$b_id"]["va"]
        elseif b["bus_type"] == 3 
            dict["$b_id"] = results[hour]["solution"]["bus"]["$b_id"]["va"]
        end
    end
end

function compute_vms(dict,grid,results,hour)
    #dict = Dict{Stri}()
    for (b_id,b) in grid["bus"]
        if b["bus_type"] != 3 && results[hour]["solution"]["bus"]["$b_id"]["va"] != 0.0
            dict["$b_id"] = 1 - results[hour]["solution"]["bus"]["$b_id"]["phi"]
        elseif b["bus_type"] == 3 
            dict["$b_id"] = 1 - results[hour]["solution"]["bus"]["$b_id"]["phi"]
        end
    end
end

function compute_diff_vas(dict,grid,results_1,results_2,hour)
    for (br_id,br) in grid["branch"]
        dict["$br_id"] = []
        f_bus = br["f_bus"]
        t_bus = br["t_bus"]
        dict["$br_id"] = abs(results_1["$hour"]["solution"]["bus"]["$f_bus"]["va"]-results_2["$hour"]["solution"]["bus"]["$t_bus"]["va"])
    end
end

function compute_diff_vms(dict,grid,results_1,results_2,hour)
    for (br_id,br) in grid["branch"]
        dict["$br_id"] = []
        f_bus = br["f_bus"]
        t_bus = br["t_bus"]
        dict["$br_id"] = abs((1-results_1["$hour"]["solution"]["bus"]["$f_bus"]["phi"])-(1-results_2["$hour"]["solution"]["bus"]["$t_bus"]["phi"]))
    end
end

function AC_lines_utilization(grid,results,dict)
    for (br_id,br) in grid["branch"]
        y = 1/(br["br_r"] + im * br["br_x"])
        g = real(y)
        b = imag(y)
        tap = br["tap"]
        angle_shift = br["shift"]
        g_fr = br["g_fr"]
        b_fr = br["b_fr"]
        tm = tap
        tr = tap .* cos.(angle_shift)
        ti = tap .* sin.(angle_shift)
        max_diff = pi/3
        vm_fr = 0.9
        vm_to = 1.1
        dict["$br_id"] =  (g)/(1-results["solution"]["bus"]["$(br["f_bus"])"]["phi"])^2 + (-g)*(1-results["solution"]["bus"]["$(br["f_bus"])"]["phi"])*(1 - results["solution"]["bus"]["$(br["t_bus"])"]["phi"])*cos(max_diff) + (-b)*(1-results["solution"]["bus"]["$(br["f_bus"])"]["phi"])*(1-results["solution"]["bus"]["$(br["t_bus"])"]["phi"])*sin(max_diff)
    end
    return dict
end

function compute_vas_single_hour(dict,grid,results)
    #dict = Dict{Stri}()
    for (b_id,b) in grid["bus"]
        if b["bus_type"] != 3 && results["solution"]["bus"]["$b_id"]["va"] != 0.0
            dict["$b_id"] = results["solution"]["bus"]["$b_id"]["va"]
        elseif b["bus_type"] == 3 
            dict["$b_id"] = results["solution"]["bus"]["$b_id"]["va"]
        end
    end
end

function compute_vms_single_hour(dict,grid,results)
    #dict = Dict{Stri}()
    for (b_id,b) in grid["bus"]
        if b["bus_type"] != 3 && results["solution"]["bus"]["$b_id"]["va"] != 0.0
            dict["$b_id"] = 1 - results["solution"]["bus"]["$b_id"]["phi"]
        elseif b["bus_type"] == 3 
            dict["$b_id"] = 1 - results["solution"]["bus"]["$b_id"]["phi"]
        end
    end
end


function compute_diff_vas_single_hour(dict,grid,results)
    for (br_id,br) in grid["branch"]
        dict["$br_id"] = []
        f_bus = br["f_bus"]
        t_bus = br["t_bus"]
        dict["$br_id"] = abs(results["solution"]["bus"]["$f_bus"]["va"]-results["solution"]["bus"]["$t_bus"]["va"])
    end
end

function compute_diff_vms_single_hour(dict,grid,results)
    for (br_id,br) in grid["branch"]
        dict["$br_id"] = []
        f_bus = br["f_bus"]
        t_bus = br["t_bus"]
        dict["$br_id"] = abs((1-results["solution"]["bus"]["$f_bus"]["phi"])-(1-results["solution"]["bus"]["$t_bus"]["phi"]))
    end
end