using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface, HiGHS
using Statistics
using KernelDensity, Distributions, StatsBase, Random
using Clustering

#########################################################################################
# Add dimensions for stochastic part
#n_scenarios = 8
n_hours = 8760
one_scenario = 1
hours = collect(1:n_hours)

start_hour_simulation = 1
end_hour_simulation = 8760
#########################################################################################
# Uploading pdf samples for offshore wind and load data for Belgium
year_wind = "2024"
folder_data = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Elia_data"

#Gaussian_samples = JSON.parsefile(joinpath(folder_data,"Gaussian_samples_8_Offshore_wind_$(year_wind)_Elia.json"))
Elia_OFW = JSON.parsefile(joinpath(folder_data,"Offshore_wind_$(year_wind)_Elia_sorted.json"))


differences_gen = [(Elia_OFW[i]["dayahead11hforecast"] - Elia_OFW[i]["measured"]) for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
capacity_factors_ofw = [Elia_OFW[i]["measured"]/Elia_OFW[i]["monitoredcapacity"] for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
is = [i for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
capacity_factors_30 = capacity_factors_ofw[start_hour_simulation:end_hour_simulation]

Load_2024 = JSON.parsefile(joinpath(folder_data,"Elia_load_$(year_wind).json"))
total_loads = [Load_2024[i]["totalload"] for i in 1:length(Load_2024)]
max_load = maximum(total_loads)

#=
# Time series
Wind_data = Dict{String,Any}()
for i in hours
    h = start_hour_simulation + i - 1
    hw = is[i]   
    Wind_data["$h"] = Dict{String,Any}()
    Wind_data["$h"]["most_recent_forecast_pu"] = Elia_OFW[hw]["mostrecentforecast"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["measured_pu"] = Elia_OFW[hw]["measured"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["P50_11hforecast_pu"] = Elia_OFW[hw]["dayahead11hforecast"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["P10_11hforecast_pu"] = Elia_OFW[hw]["dayahead11hconfidence90"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["P90_11hforecast_pu"] = Elia_OFW[hw]["dayahead11hconfidence10"]/Elia_OFW[hw]["monitoredcapacity"]
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

measured_wind   = [Wind_data["$i"]["measured_pu"]  for i in 1:length(hours)]
forecasted_wind = [Wind_data["$i"]["P50_11hforecast_pu"] for i in 1:length(hours)]
load_pu = [Load_data["$i"]["total_load_pu"] for i in 1:length(hours)]
=#


P50_11h = []
P90_11h = []
P10_11h = []
measured = []
for i in 1:length(Elia_OFW)
    if Elia_OFW[i]["minute"] == "00"
        push!(P50_11h,Elia_OFW[i]["dayahead11hforecast"]/Elia_OFW[i]["monitoredcapacity"])
        push!(P90_11h,Elia_OFW[i]["dayahead11hconfidence90"]/Elia_OFW[i]["monitoredcapacity"])
        push!(P10_11h,Elia_OFW[i]["dayahead11hconfidence10"]/Elia_OFW[i]["monitoredcapacity"])
        push!(measured,Elia_OFW[i]["measured"]/Elia_OFW[i]["monitoredcapacity"])
    end
end
diff_measured_P50 = measured .- P50_11h

P50_11h_quarterly = []
P90_11h_quarterly = []
P10_11h_quarterly = []
measured_quarterly = []
for i in 1:length(Elia_OFW)
        push!(P50_11h_quarterly,Elia_OFW[i]["dayahead11hforecast"]/Elia_OFW[i]["monitoredcapacity"])
        push!(P90_11h_quarterly,Elia_OFW[i]["dayahead11hconfidence90"]/Elia_OFW[i]["monitoredcapacity"])
        push!(P10_11h_quarterly,Elia_OFW[i]["dayahead11hconfidence10"]/Elia_OFW[i]["monitoredcapacity"])
        push!(measured_quarterly,Elia_OFW[i]["measured"]/Elia_OFW[i]["monitoredcapacity"])
end

diff_measured_P50_quarterly = measured_quarterly .- P50_11h_quarterly



scatter(P50_11h, label = "P50 11h forecast", xlabel = "Hour", ylabel = "Capacity factor [-]")
scatter(P90_11h, label = "P90 11h forecast")
scatter(P10_11h, label = "P10 11h forecast")


diff_P50_P10 = P50_11h .- P10_11h
count(>(0), diff_P50_P10)  # Count how many times P50 is greater than P10

diff_P90_P50 = P90_11h .- P50_11h
count(>(0), diff_P90_P50)  # Count how many times P90 is greater than P50

diff_measured_P10 = measured .- P10_11h
count(>(0), diff_measured_P10)/length(diff_measured_P10)  # % of hours in which measured is higher than P10
1 - 0.83094

diff_measured_P10_quarterly = measured_quarterly .- P10_11h_quarterly
count(>(0), diff_measured_P10_quarterly)/length(diff_measured_P10_quarterly)  # % of hours in which measured is higher than P10
1 - 0.8292
# -> 17% vs 10% at max lol

diff_P90_measured = P90_11h .- measured 
count(>(0), diff_P90_measured)/length(diff_P90_measured)  # Count how many times P90 is greater than P50
1 - 0.95196
# -> 4.81% of hours in which measured is higher than P90, 10% at max

diff_P90_measured_quarterly = P90_11h_quarterly .- measured_quarterly 
count(>(0), diff_P90_measured_quarterly)/length(diff_P90_measured_quarterly)  # Count how many times P90 is greater than P50
1 - 0.9507

diff_P50_measured_quarterly = P50_11h_quarterly - measured_quarterly
count(>(0), diff_P50_measured_quarterly)/length(diff_P50_measured_quarterly)
1 - 0.6109

scatter(measured,diff_measured_P50,ylabel = "Difference between measured and forecasted values",xlabel = "Measured capacity factor [-]", label = :none, ylabelfontsize = 8, xlabelfontsize = 8, xlims = (-0.05,1.0), ylims = (-1.0,1.0), yticks = -1.0:0.2:1.0)
avg_measured = mean(measured)
avg_forecasted = mean(P50_11h)
vline!([avg_measured], label = "Mean measured value", color = :red, lw=2)
vline!([avg_forecasted], label = "Mean forecasted value", color = :brown, lw=2)

figures_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/IJEPES_paper/Figures/RES_uncertainty"
savefig(joinpath(figures_folder, "Difference_measured_P50_$(year_wind).pdf"))
savefig(joinpath(figures_folder, "Difference_measured_P50_$(year_wind).svg"))




scatter(measured_quarterly,diff_measured_P50_quarterly,ylabel = "Difference between measured and forecasted values",xlabel = "Measured capacity factor [-]", label = :none, ylabelfontsize = 8, xlabelfontsize = 8, xlims = (-0.05,1.0), ylims = (-1.0,1.0), yticks = -1.0:0.2:1.0)
avg_measured_quarterly = mean(measured_quarterly)
avg_forecasted_quarterly = mean(P50_11h_quarterly)
vline!([avg_measured_quarterly], label = "Mean measured value", color = :red, lw=2)
vline!([avg_forecasted_quarterly], label = "Mean forecasted value", color = :brown, lw=2)

figures_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/IJEPES_paper/Figures/RES_uncertainty"
savefig(joinpath(figures_folder, "Difference_measured_P50_$(year_wind)_quarterly.pdf"))
savefig(joinpath(figures_folder, "Difference_measured_P50_$(year_wind)_quarterly.svg"))






sorted_diff_measured_P50 = sort(diff_measured_P50)
sorted_diff_measured_P50_quarterly = sort(diff_measured_P50_quarterly)

# Computing pdf
kde_ = kde(sorted_diff_measured_P50)
kde_quarterly = kde(sorted_diff_measured_P50_quarterly)

pdf_value = pdf(kde_, 0.045)

plot(kde_.x, kde_.density, label="Probability density function", lw=2, xlabel = "Capacity factor difference between measured D and forecasted D-1 value [-]",xlabelfontsize = 9,xlims = (-1.0, 1.0),ylims = (-0.1,11), ylabel = "Probability density [-]",ylabelfontsize = 9, grid = :none, legend=:topright)
histogram!(sorted_diff_measured_P50, norm=true, alpha=0.3, label= :none)
hline!([0.0], label = :none, color = :black)
savefig(joinpath(figures_folder, "pdf_wind_forecast_error.pdf"))
savefig(joinpath(figures_folder, "pdf_wind_forecast_error.svg"))


plot(kde_quarterly.x, kde_quarterly.density, label="Probability density function", lw=2, xlabel = "Capacity factor difference between measured D and forecasted D-1 value [-]",xlabelfontsize = 9,xlims = (-1.0, 1.0),ylims = (-0.1,11), ylabel = "Probability density [-]",ylabelfontsize = 9, grid = :none, legend=:topright)
histogram!(sorted_diff_measured_P50_quarterly, norm=true, alpha=0.3, label=:none)
hline!([0.0], label = :none, color = :black)
savefig(joinpath(figures_folder, "pdf_wind_forecast_error_quarterly.pdf"))
savefig(joinpath(figures_folder, "pdf_wind_forecast_error_quarterly.svg"))


laplace_fit = fit(Laplace, diff_measured_P50)
println("Fitted Laplace: μ = $(mean(laplace_fit)), σ = $(std(laplace_fit))")

laplace_fit_quarterly = fit(Laplace, diff_measured_P50_quarterly)
println("Fitted Laplace: μ = $(mean(laplace_fit_quarterly)), σ = $(std(laplace_fit_quarterly))")

#Looking at this PDF (difference between measured and D-1 forecasted offshore wind capacity factor), here are key features:
#	•	Sharp peak at zero → High frequency of small errors.
#	•	Heavy tails → Large errors are rare but more frequent than a Gaussian assumption would suggest.
#	•	Asymmetry is minimal → Looks fairly symmetric around zero.

#Candidate Distributions:
#	1.	Laplace (Double Exponential) Distribution
#	•	Sharp peak at the center, heavier tails than Gaussian.
#	•	Common for modeling forecast errors with fat tails.
#	•	PDF:
#f(x|\mu, b) = \frac{1}{2b} \exp\left(-\frac{|x - \mu|}{b}\right)


# Generate wind scenarios -> example
N = 10000
sampled_errors = rand(laplace_fit,N)
scenarios = sampled_errors
#clamped_scenarios = clamp.(scenarios, 0.0, 1.0)

# Checking the two histograms
histogram(scenarios, bins=100, normalize=true, label="Sample scenarios", xlims = [-1.0,1.0],ylims = [0.0,7.0])
savefig(joinpath(figures_folder, "Sample_scenarios_histogram_$N.pdf"))
savefig(joinpath(figures_folder, "Sample_scenarios_histogram_$N.svg"))

histogram(diff_measured_P50, bins=100, normalize=true, label="Difference measured - forecast", xlims = [-1.0,1.0],ylims = [0.0,7.0])
savefig(joinpath(figures_folder, "pdf_histogram.pdf"))
savefig(joinpath(figures_folder, "pdf_histogram.svg"))

histogram(scenarios, bins=100, normalize=true, label="Sample scenarios", xlims = [-1.0,1.0],ylims = [0.0,7.0])
histogram!(diff_measured_P50, bins=100, normalize=true, label="Difference measured - forecast", xlims = [-1.0,1.0],ylims = [0.0,7.0])
savefig(joinpath(figures_folder, "Sample_scenarios_histogram_$(N)_vs_pdf_histogram.pdf"))
savefig(joinpath(figures_folder, "Sample_scenarios_histogram_$(N)_vs_pdf_histogram.svg"))



#=
sampled_errors_prob = []
for i in 1:length(sampled_errors)
    push!(sampled_errors_prob, pdf(kde_, sampled_errors[i]))
end
sampled_errors_rel_prob = sampled_errors_prob ./ sum(sampled_errors_prob)
sum(sampled_errors_rel_prob)

scatter(sampled_errors)
=#
######################
# Create scenarios
n_scenarios = 4

function create_scenarios_per_hour(n,pdf,samples,value)
    X = reshape(samples, 1, :)
    result = kmeans(X, n)
    centers_means = result.centers[1, :]

    pdf_values_centers = KernelDensity.pdf(pdf, centers_means)
    pdf_values_centers_rel_prob = pdf_values_centers ./ sum(pdf_values_centers)

    scenarios = value .+ centers_means
    clamped_scenarios = clamp.(scenarios, 0.0, 1.0)
    centers_means_clamped = clamped_scenarios .- value
    pdf_values_centers_clamped = KernelDensity.pdf(kde_, centers_means_clamped)
    pdf_values_centers_rel_prob_clamped = pdf_values_centers_clamped ./ sum(pdf_values_centers_clamped)
    return centers_means_clamped, pdf_values_centers_rel_prob_clamped
end
#=
a, b = create_scenarios_per_hour(6, kde_, sampled_errors, P50_11h[1])

# Clustering.jl expects columns to be data points; reshape to 1 row, N columns
X = reshape(sampled_errors, 1, :)

# Perform k-medoids clustering with k= n_scenarios
result = kmeans(X, n_scenarios)

# Display results
println("Cluster centers: ", result.centers)
println("Assignments: ", result.assignments)

centers_means = result.centers[1, :]
scatter(centers_means)

# Show clusters per number
pdf_values_centers = pdf(kde_, centers_means)
pdf_values_centers_rel_prob = pdf_values_centers ./ sum(pdf_values_centers)

try_forecast = forecasted_wind[1] .+ centers_means
clamped_forecast = clamp.(try_forecast, 0.0, 1.0)
centers_means_clamped = clamped_forecast .- forecasted_wind[1] 
pdf_values_centers_clamped = pdf(kde_, centers_means_clamped)
pdf_values_centers_rel_prob_clamped = pdf_values_centers_clamped ./ sum(pdf_values_centers_clamped)
=#

##############
first_hour = 355
last_hour  = 378

forecasted_wind = P50_11h[first_hour:last_hour]
measured_wind   = measured[first_hour:last_hour]
hours_simulation_Elia = collect(first_hour:last_hour)
laplace_fit = fit(Laplace, diff_measured_P50)
sorted_diff_measured_P50 = sort(diff_measured_P50)
kde_ = kde(sorted_diff_measured_P50)

n_hours = last_hour - first_hour + 1
start_hour_simulation = 1
end_hour_simulation = last_hour - first_hour + 1
hours = collect(start_hour_simulation:end_hour_simulation)

expected_value_wind = []
scenarios_wind = Dict{String,Any}()
count_hour = 0
forecasted_wind = JSON.parsefile(joinpath(@__DIR__,"case30","forecasted_wind_hours_355_378_modified.json"))
measured_wind = JSON.parsefile(joinpath(@__DIR__,"case30","measured_wind_355_378_modified.json"))

for i in hours_simulation_Elia
    count_hour += 1
    expected_value_wind_hourly = 0.0  
    hourly_forecasted_value = forecasted_wind[count_hour]
    N = 10000
    sampled_errors = rand(laplace_fit,N)
    smaples = sampled_errors
    values, rel_probs = create_scenarios_per_hour(n_scenarios,kde_,smaples,hourly_forecasted_value)
    for s in 1:n_scenarios
        n = (count_hour - 1)*n_scenarios + s
        scenarios_wind["$n"] = Dict{String,Any}()
        scenarios_wind["$n"]["probability"] = deepcopy(rel_probs[s])
        scenarios_wind["$n"]["samples_pu"] = deepcopy(hourly_forecasted_value + values[s])
        scenarios_wind["$n"]["hour"] = i
        scenarios_wind["$n"]["scenario"] = s
        expected_value_wind_hourly += rel_probs[s] * values[s]
    end
    push!(expected_value_wind, expected_value_wind_hourly)
end

case = "case30"
json_scenarios_wind = JSON.json(scenarios_wind)
open(joinpath(@__DIR__,case,"Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_scenarios_wind) 
end 
 
##############################
n_scenarios = 12
n_hours = 24

scenarios_wind_plot = JSON.parsefile(joinpath(@__DIR__,"case30","Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"))
forecasted_wind_plot = forecasted_wind
measured_wind_plot   = measured_wind

probs = [scenarios_wind_plot["$s"]["probability"] for s in 1:(n_hours*n_scenarios)]
samples = [scenarios_wind_plot["$s"]["samples_pu"] for s in 1:(n_hours*n_scenarios)]

p1 = plot(xlabel = "Hour", ylabel = "Capacity factor",xlims = (0,24),xticks = 1:1:24)
for h in 1:n_hours
    vector_samples = []
    for s in 1:n_scenarios
        n = (h - 1)*n_scenarios + s
        push!(vector_samples,scenarios_wind_plot["$n"]["samples_pu"])
    end
    hours_x = h*ones(n_scenarios)
    scatter!(p1, hours_x, vector_samples, color = :lightblue, label = :none)
end
plot!(p1,forecasted_wind,label = "Forecasted wind",color = :orange)
plot!(p1,measured_wind,label = "Measured wind",color = :blue)

savefig(joinpath(figures_folder, "Laplace_$(n_scenarios)_scenarios_.pdf"))
savefig(joinpath(figures_folder, "Laplace_$(n_scenarios)_scenarios_.svg"))

## Processing saved wind json files
#=
average_wind = JSON.parsefile(joinpath(input_folder,"case30","average_wind_355_378_modified.json"))
scenario_wind_4 = JSON.parsefile(joinpath(input_folder,"case30","scenario_wind_4_355_378_modified.json"))
scenario_wind_8 = JSON.parsefile(joinpath(input_folder,"case30","scenario_wind_8_355_378_modified.json"))
scenario_wind_6 = JSON.parsefile(joinpath(@__DIR__,"case30","Laplace_6_scenarios_355_378.json"))


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
=#

