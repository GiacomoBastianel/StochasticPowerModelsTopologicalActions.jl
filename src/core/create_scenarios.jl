using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface, HiGHS
using Statistics
using KernelDensity, Distributions, StatsBase, Random

#########################################################################################
# Add dimensions for stochastic part
n_scenarios = 8
n_hours = 24
one_scenario = 1
hours = collect(1:n_hours)

#########################################################################################
# Uploading pdf samples for offshore wind and load data for Belgium
year_wind = "2024"
folder_data = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Elia_data"

Gaussian_samples = JSON.parsefile(joinpath(folder_data,"Gaussian_samples_8_Offshore_wind_$(year_wind)_Elia.json"))
Elia_OFW = JSON.parsefile(joinpath(folder_data,"Offshore_wind_$(year_wind)_Elia_sorted.json"))

differences_gen = [(Elia_OFW[i]["dayahead11hforecast"] - Elia_OFW[i]["measured"]) for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
capacity_factors_ofw = [Elia_OFW[i]["measured"]/Elia_OFW[i]["monitoredcapacity"] for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
is = [i for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
capacity_factors_30 = capacity_factors_ofw[start_hour_simulation:end_hour_simulation]

Load_2024 = JSON.parsefile(joinpath(folder_data,"Elia_load_$(year_wind).json"))
total_loads = [Load_2024[i]["totalload"] for i in 1:length(Load_2024)]
max_load = maximum(total_loads)

# Time series
Wind_data = Dict{String,Any}()
for i in hours
    h = start_hour_simulation + i - 1
    hw = is[i]   
    Wind_data["$h"] = Dict{String,Any}()
    Wind_data["$h"]["most_recent_forecast_pu"] = Elia_OFW[hw]["mostrecentforecast"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["measured_pu"] = Elia_OFW[hw]["measured"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["P50_11hforecast_pu"] = Elia_OFW[hw]["dayahead11hforecast"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["samples_pu"] = Gaussian_samples["$hw"]["samples_pu"]
    Wind_data["$h"]["pdf_normalized"] = Gaussian_samples["$hw"]["pdf_normalized"]
    Wind_data["$h"]["Elia_timestep"] = is[i]
end

Load_data = Dict{String,Any}()
for i in hours
    h = start_hour_simulation + i - 1
    hw = is[i]   
    Load_data["$h"] = Dict{String,Any}()
    Load_data["$h"]["total_load"] = Load_2024[hw]["totalload"]
    Load_data["$h"]["total_load_pu"] = Load_2024[hw]["totalload"]/max_load
    Load_data["$h"]["Elia_timestep"] = is[i]
end


measured_wind   = [Wind_data["$i"]["measured_pu"]   for i in 1:length(hours)]
forecasted_wind = [Wind_data["$i"]["P50_11hforecast_pu"] for i in 1:length(hours)]
load_pu = [Load_data["$i"]["total_load_pu"] for i in 1:length(hours)]


P50_11h = []
for i in 1:length(Elia_OFW)
    if Elia_OFW[i]["minute"] == "00"
        push!(P50_11h,Elia_OFW[i]["dayahead11hforecast"]/Elia_OFW[i]["monitoredcapacity"])
    end
end

measured_11h = []
for i in 1:length(Elia_OFW)
    if Elia_OFW[i]["minute"] == "00"
        push!(measured_11h,Elia_OFW[i]["measured"]/Elia_OFW[i]["monitoredcapacity"])
    end
end

diff_ = measured_11h .- P50_11h
scatter(diff_)
histogram(diff_, bins=50, normalize=true,xticks = -1.0:0.1:1.0,xlims = (-1.0,1.0),
ylims = (0,8),xlabel = "Forecast error [pu]",ylabel = "Probability density [-]",
color = :green,legend =:none,grid = :none, xlabelfontsize = 10,ylabelfontsize = 10)

normal_fit = fit(Normal, diff_)
println("Fitted Normal: μ = $(mean(normal_fit)), σ = $(std(normal_fit))")


forecast = 0.9663144865390567  # e.g., forecasted wind power in MW
N = 10000          # number of scenarios
N_4 = 4
N_8 = 8


sorted_diff_ = sort(diff_)
kde_ = kde(sorted_diff_)
pdf_value = pdf(kde_, 0.045)

plot(kde_.x, kde_.density, label="KDE", lw=2, xlabel = "Capacity factor difference between measured D and forecasted D-1 value [-]",xlabelfontsize = 9,xlims = (-1.0, 1.0),ylims = (-0.1,11), ylabel = "Probability density [-]",ylabelfontsize = 9, grid = :none, legend=:topright)
histogram!(diff_, norm=true, alpha=0.3, label="Histogram")
hline!([0.0], label = :none, color = :black)
figures_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/IJEPES_paper/Figures/RES_uncertainty"
savefig(joinpath(figures_folder, "kde_wind_forecast_error.pdf"))
savefig(joinpath(figures_folder, "kde_wind_forecast_error.svg"))

n_scenarios = 10

# Generate wind scenarios -> example
sampled_errors = rand(normal_fit, N)
scenarios = forecast .+ sampled_errors
clamped_scenarios = clamp.(scenarios, 0.0, 1.0)

sampled_errors_4 = rand(normal_fit, N_4)
scenarios_4 = forecast .+ sampled_errors_4
clamped_scenarios_4 = clamp.(scenarios_4, 0.0, 1.0)

sampled_errors_8 = rand(normal_fit, N_8)
scenarios_8 = forecast .+ sampled_errors_8
clamped_scenarios_8 = clamp.(scenarios_8, 0.0, 1.0)

histogram(clamped_scenarios, bins=50, normalize=true, label="Scenarios")
vline!([forecast], label="Forecast", lw=2, lc=:red)

histogram(clamped_scenarios_4, bins=50, normalize=true, label="Scenarios")
vline!([forecast], label="Forecast", lw=2, lc=:red)

histogram(clamped_scenarios_8, bins=50, normalize=true, label="Scenarios")
vline!([forecast], label="Forecast", lw=2, lc=:red)


sampled_errors_prob = []
for i in 1:length(sampled_errors_4)
    push!(sampled_errors_prob, pdf(kde_, sampled_errors_4[i]))
end
sampled_errors_rel_prob = sampled_errors_prob ./ sum(sampled_errors_prob)


first_hour = 355
last_hour  = 378

forecasted_wind = P50_11h[first_hour:last_hour]
measured_wind   = measured_11h[first_hour:last_hour]
hours_simulation_Elia = collect(first_hour:last_hour)

n_hours = last_hour - first_hour + 1
start_hour_simulation = 1
end_hour_simulation = last_hour - first_hour + 1
hours = collect(start_hour_simulation:end_hour_simulation)
n_scenarios = 4
one_scenario = 1


expected_value_wind = []
scenarios_wind = Dict{String,Any}()
count_hour = 0
for i in hours_simulation_Elia
    count_hour += 1
    expected_value_wind_hourly = 0.0  
    for s in 1:n_scenarios
        n = (count_hour - 1)*n_scenarios + s
        scenarios_wind["$n"] = Dict{String,Any}()
        scenarios_wind["$n"]["probability"] = deepcopy(Gaussian_samples["$i"]["pdf_normalized"][s])
        scenarios_wind["$n"]["samples_pu"] = deepcopy(Gaussian_samples["$i"]["samples_pu"][s])
        scenarios_wind["$n"]["hour"] = i
        scenarios_wind["$n"]["scenario"] = s
        expected_value_wind_hourly += Gaussian_samples["$i"]["samples_pu"][s]*Gaussian_samples["$i"]["pdf_normalized"][s]
    end
    push!(expected_value_wind, expected_value_wind_hourly)
end

## Processing saved wind json files
measured_wind = JSON.parsefile(joinpath(input_folder,"case30","measured_wind_355_378_modified.json"))
average_wind = JSON.parsefile(joinpath(input_folder,"case30","average_wind_355_378_modified.json"))
forecasted_wind = JSON.parsefile(joinpath(input_folder,"case30","forecasted_wind_hours_355_378_modified.json"))
scenario_wind_4 = JSON.parsefile(joinpath(input_folder,"case30","scenario_wind_4_355_378_modified.json"))
scenario_wind_8 = JSON.parsefile(joinpath(input_folder,"case30","scenario_wind_8_355_378_modified.json"))


scenario_1 = measured_wind
scenario_4 = forecasted_wind
scenario_diff_1 = measured_wind .- measured_wind
scenario_diff_4 = measured_wind .- forecasted_wind
prob_scenario_1 = [pdf(kde_, i) for i in scenario_diff_1]
prob_scenario_4 = [pdf(kde_, i) for i in scenario_diff_4]

scenario_diff = measured_wind .- forecasted_wind
scenario_diff_2 = scenario_diff/3*2
scenario_diff_3 = scenario_diff/3
scenario_2 = scenario_4 .+ scenario_diff_2
prob_scenario_2 = [pdf(kde_, i) for i in scenario_diff_2]
prob_scenario_3 = [pdf(kde_, i) for i in scenario_diff_3]
scenario_3 = scenario_4 .+ scenario_diff_3

scenarios_wind_adjusted = Dict{String,Any}()
count_hour = 0
for i in hours_simulation_Elia
    count_hour += 1
    expected_value_wind_hourly = 0.0  
    for s in 1:n_scenarios
        n = (count_hour - 1)*n_scenarios + s
        if s == 1
            scenarios_wind_adjusted["$n"] = Dict{String,Any}()
            scenarios_wind_adjusted["$n"]["probability_abs"] = deepcopy(prob_scenario_1[count_hour])
            scenarios_wind_adjusted["$n"]["samples_pu"] = deepcopy(scenario_1[count_hour])
            scenarios_wind_adjusted["$n"]["error"] = deepcopy(scenario_diff_1[count_hour])
            scenarios_wind_adjusted["$n"]["sampled_error"] = deepcopy(scenario_diff_1[count_hour])
            scenarios_wind_adjusted["$n"]["hour"] = i
            scenarios_wind_adjusted["$n"]["scenario"] = s
        elseif s == 2
            scenarios_wind_adjusted["$n"] = Dict{String,Any}()
            scenarios_wind_adjusted["$n"]["probability_abs"] = deepcopy(prob_scenario_2[count_hour])
            scenarios_wind_adjusted["$n"]["samples_pu"] = deepcopy(scenario_2[count_hour])
            scenarios_wind_adjusted["$n"]["error"] = deepcopy(scenario_diff_2[count_hour])
            scenarios_wind_adjusted["$n"]["sampled_error"] = deepcopy(scenario_diff_2[count_hour])
            scenarios_wind_adjusted["$n"]["hour"] = i
            scenarios_wind_adjusted["$n"]["scenario"] = s
        elseif s == 3
            scenarios_wind_adjusted["$n"] = Dict{String,Any}()
            scenarios_wind_adjusted["$n"]["probability_abs"] = deepcopy(prob_scenario_3[count_hour])
            scenarios_wind_adjusted["$n"]["samples_pu"] = deepcopy(scenario_3[count_hour])
            scenarios_wind_adjusted["$n"]["error"] = deepcopy(scenario_diff_3[count_hour])
            scenarios_wind_adjusted["$n"]["sampled_error"] = deepcopy(scenario_diff_3[count_hour])
            scenarios_wind_adjusted["$n"]["hour"] = i
            scenarios_wind_adjusted["$n"]["scenario"] = s
        elseif s == 4
            scenarios_wind_adjusted["$n"] = Dict{String,Any}()
            scenarios_wind_adjusted["$n"]["probability_abs"] = deepcopy(prob_scenario_4[count_hour])
            scenarios_wind_adjusted["$n"]["samples_pu"] = deepcopy(scenario_4[count_hour])
            scenarios_wind_adjusted["$n"]["error"] = deepcopy(scenario_diff_4[count_hour])
            scenarios_wind_adjusted["$n"]["sampled_error"] = deepcopy(scenario_diff_4[count_hour])
            scenarios_wind_adjusted["$n"]["hour"] = i
            scenarios_wind_adjusted["$n"]["scenario"] = s
        end
    end
    tot_prob = sum([scenarios_wind_adjusted["$n"]["probability_abs"] for n in ((count_hour - 1)*n_scenarios + 1):((count_hour - 1)*n_scenarios + 4)])
    for s in 1:n_scenarios
        n = (count_hour - 1)*n_scenarios + s
        scenarios_wind_adjusted["$n"]["probability"] = deepcopy(scenarios_wind_adjusted["$n"]["probability_abs"])/tot_prob
    end
end

json_scenarios_wind_adjusted = JSON.json(scenarios_wind_adjusted)
open(joinpath(results_folder,case,"scenario_wind_4_$(first_hour)_$(last_hour)_adjusted.json"),"w") do f 
    write(f, json_scenarios_wind_adjusted) 
end 

open(joinpath(@__DIR__,"case30","scenario_wind_4_$(first_hour)_$(last_hour)_adjusted.json"),"w") do f 
    write(f, json_scenarios_wind_adjusted) 
end 

# Plotting the scenarios
scatter(scenario_1,xticks = 1:1:24,label = "Measured (scenario 1)")
scatter!(scenario_2,label = "Scenario 2")
scatter!(scenario_3, label = "Scenario 3")
scatter!(scenario_4,label = "Forecasted (scenario 4)")
savefig(joinpath(figures_folder, "Scenarios_adjusted.pdf"))
savefig(joinpath(figures_folder, "Scenarios_adjusted.svg"))


