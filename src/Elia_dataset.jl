# File to treat Elia's data
using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using Gurobi
using JuMP
using DataFrames
using CSV
using InfrastructureModels
#using Plots
using Feather
using JSON
using Ipopt
using Juniper
using Distributions



gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer)
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer)
juniper = JuMP.optimizer_with_attributes(Juniper.Optimizer, "nl_solver" => ipopt, "mip_solver" => gurobi, "time_limit" => 36000)

##################################################################
## Processing input data
folder_data = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Elia_data"

# Belgium grid without energy island
W_2023_file = joinpath(folder_data,"Offshore_wind_2024_Elia.json")
W_2023 = JSON.parsefile(W_2023_file)


offshore_timesteps = []
for i in 1:length(W_2023)
    if W_2023[i]["offshoreonshore"] == "Offshore"
        push!(offshore_timesteps,W_2023[i])
    end
end
offshore_timesteps_ordered = reverse(offshore_timesteps)

for i in 1:length(offshore_timesteps_ordered)
    offshore_timesteps_ordered[i]["day"] = offshore_timesteps_ordered[i]["datetime"][9:10]
    offshore_timesteps_ordered[i]["month"] = offshore_timesteps_ordered[i]["datetime"][6:7]
    offshore_timesteps_ordered[i]["year"] = offshore_timesteps_ordered[i]["datetime"][1:4]
    offshore_timesteps_ordered[i]["hour"] = "$(parse(Int64,offshore_timesteps_ordered[i]["datetime"][12:13])+1)"
    offshore_timesteps_ordered[i]["minute"] = offshore_timesteps_ordered[i]["datetime"][15:16]
    if offshore_timesteps_ordered[i]["minute"] == "00"
        offshore_timesteps_ordered[i]["quarter"] = "1"
    elseif offshore_timesteps_ordered[i]["minute"] == "15"
        offshore_timesteps_ordered[i]["quarter"] = "2"
    elseif offshore_timesteps_ordered[i]["minute"] == "30"
        offshore_timesteps_ordered[i]["quarter"] = "3"
    elseif offshore_timesteps_ordered[i]["minute"] == "45"
        offshore_timesteps_ordered[i]["quarter"] = "4"
    end
end

json_string = JSON.json(offshore_timesteps_ordered)
open(joinpath(folder_data,"Offshore_wind_2024_Elia_sorted.json"),"w") do f 
    write(f, json_string) 
end



function compute_pdfs(dict,dict_samples,n_samples)
    for i in 1:length(dict)
        if !isnothing(dict[i]["dayahead11hconfidence90"])
            P_90_timestep = dict[i]["dayahead11hconfidence90"]
            P_10_timestep = dict[i]["dayahead11hconfidence10"]
            P_50_timestep = dict[i]["dayahead11hforecast"]
        else
            P_90_timestep = dict[i]["dayaheadconfidence90"]
            P_10_timestep = dict[i]["dayaheadconfidence10"]
            P_50_timestep = dict[i]["dayahead11hforecast"]
        end
        X = dict[i]["monitoredcapacity"]
        z_010 = -1.2816
        z_090 = 1.2816
        sigma_timestep = (P_90_timestep - P_10_timestep)/(2*z_090)
        mu = P_50_timestep
        td = Truncated(Normal(mu,sigma_timestep), 0.0, X)
        samples_timestep = rand(td, n_samples)
        #x_timestep = range(n_samples - 3*sigma_timestep, n_samples + 3*sigma_timestep, length=n_samples)
        pdf_timestep = pdf.(td, samples_timestep)
        normalized_pdf_timestep = pdf_timestep/sum(pdf_timestep)
        dict_samples["$i"] = Dict{String,Any}()
        dict_samples["$i"]["samples"] = samples_timestep
        dict_samples["$i"]["samples_pu"] = samples_timestep/dict[i]["monitoredcapacity"]
        dict_samples["$i"]["pdf_original"] = pdf_timestep
        dict_samples["$i"]["pdf_normalized"] = normalized_pdf_timestep
        dict_samples["$i"]["std"] = sigma_timestep
        dict_samples["$i"]["mu"] = P_50_timestep
        dict_samples["$i"]["datetime"] = deepcopy(dict[i]["datetime"])
        dict_samples["$i"]["day"]   = dict[i]["day"]  
        dict_samples["$i"]["month"] = dict[i]["month"] 
        dict_samples["$i"]["year"]  = dict[i]["year"] 
        dict_samples["$i"]["hour"]  = dict[i]["hour"] 
        dict_samples["$i"]["minute"]= dict[i]["minute"]
    end
end

Gaussian_samples_8 = Dict{String,Any}()
compute_pdfs(offshore_timesteps_ordered,Gaussian_samples_8,8)

Gaussian_samples_100 = Dict{String,Any}()
compute_pdfs(offshore_timesteps_ordered,Gaussian_samples_100,100)

json_string = JSON.json(Gaussian_samples_8)
open(joinpath(folder_data,"Gaussian_samples_8_Offshore_wind_2024_Elia.json"),"w") do f 
    write(f, json_string) 
end

json_string = JSON.json(Gaussian_samples_100)
open(joinpath(folder_data,"Gaussian_samples_100_Offshore_wind_2024_Elia.json"),"w") do f 
    write(f, json_string) 
end



