## requirements
using Agents
using StatsBase
using DataFrames
using Feather
using Query
using Pipe
using Random
using ProgressMeter

## model
mutable struct AxelrodAgent <: Agents.AbstractAgent
    id::Int
    pos::NTuple{2, Int}
    stubborn::Bool
    culture::AbstractArray
end

function initialize_model(dims::NTuple{2, Int}, stubborn_positions::AbstractArray)
    space = Agents.GridSpace(dims, periodic=false, moore=false)
    model = Agents.AgentBasedModel(AxelrodAgent, space, scheduler=random_activation)
    populate!(model, dims)
    to_stubborn!(stubborn_positions, model)
    return model
end

function populate!(model::Agents.AgentBasedModel, dims::NTuple{2, Int})
    positions = [(i, j) for i in 1:dims[1] for j in 1:dims[2]]
    for (id, pos) in enumerate(positions)
        Agents.add_agent_pos!(AxelrodAgent(id, pos, false, rand(0:9, 5)), model)
    end
    return model
end

function to_stubborn!(positions::Array{NTuple{2, Int}}, model::Agents.AgentBasedModel)
    for pos in positions
        stubborn_agent = Agents.get_node_agents(Agents.coord2vertex(pos, model), model)[1]
        stubborn_agent.stubborn = true
        stubborn_agent.culture = zeros(Int64, 5)
    end
    return model
end

function agent_step!(agent::Agents.AbstractAgent, model::Agents.AgentBasedModel)
    neighbors = Agents.node_neighbors(agent, model)
    interaction_partner_pos = StatsBase.sample(neighbors)
    interaction_partner = Agents.get_node_agents(
        Agents.coord2vertex(interaction_partner_pos, model), model
    )[1]
    similarity = StatsBase.mean(agent.culture .== interaction_partner.culture)
    if !(similarity == 1.0) & !agent.stubborn & (rand() <= similarity)
        assimilate!(agent, interaction_partner)
    end
    return agent
end

function assimilate!(agent::Agents.AbstractAgent, interaction_partner::Agents.AbstractAgent)
	random_attr = rand(1:length(agent.culture))
	if !(agent.culture[random_attr] == interaction_partner.culture[random_attr])
		agent.culture[random_attr] = interaction_partner.culture[random_attr]
	else
		assimilate!(agent, interaction_partner)
	end
	return agent
end

function prepare_data!(dataframe::DataFrames.DataFrame, config_name::String)
    dataframe[!, "culture"] = [join(c) for c in dataframe[!, "culture"]]
    dataframe[!, :x] = [i[1] for i in dataframe[!, :pos]]
    dataframe[!, :y] = [i[2] for i in dataframe[!, :pos]]
    DataFrames.select!(dataframe, DataFrames.Not(:pos))
    dataframe[!, :config] .= config_name
    return dataframe
end

function run_random(; steps::Int, replicates::Int, by::Int=10, rnd_seed::Int=0, write::Bool=false)
    Random.seed!(rnd_seed)
    agent_df_list = DataFrames.DataFrame[]
    p = ProgressMeter.Progress(replicates, "Running Simulations ...")
    for i in 1:replicates
        config = [(rand(1:10), rand(1:10)) for j in 1:4]
        model = initialize_model((10, 10), config)
        rep_df, _ = Agents.run!(
            model, agent_step!, steps, adata=[:pos, :culture],
            replicates=1, when=0:by:steps, parallel=true, obtainer=deepcopy
        )
        rep_df[!, :replicate] .= i
        push!(agent_df_list, deepcopy(rep_df))
        ProgressMeter.next!(p)
    end
    agent_df = reduce(vcat, agent_df_list)
    prepare_data!(agent_df, "random")
    if write
        Feather.write(joinpath("data", "random.feather"), agent_df)
    end
    return agent_df
end

## configurations
baseline = NTuple{2, Int}[]
line_edge = [(1, 1), (1, 2), (1, 3), (1, 4)]
line_center = [(5, 3), (5, 4), (5, 5), (5, 6)]
square_corner = [(1, 1), (1, 2), (2, 1), (2, 2)]
square_center = [(5, 5), (5, 6), (6, 5), (6, 6)]
corners = [(1, 1), (1, 10), (10, 1), (10, 10)]
diagonal = [(1, 1), (4, 4), (7, 7), (10, 10)]
distance_center = [(4, 4), (4, 7), (7, 4), (7, 7)]
config_list = [
    baseline, line_edge, line_center, square_corner, 
    square_center, corners, diagonal, distance_center
]
filename_list = [
    "baseline", "line_edge", "line_center", "square_corner", 
    "square_center", "corners", "diagonal", "distance_center"
]

## simulations
Agents.run!(
    initialize_model((10, 10), baseline), agent_step!, 100, adata=[:pos, :culture],
    replicates=5, when=0:10:100, parallel=true, obtainer=deepcopy
)  # index run 1
run_random(steps=100, replicates=3, by=10, rnd_seed=0, write=false)  # index run 2

if !("data" in readdir())
    mkdir("data")
end

p = ProgressMeter.Progress(length(config_list), "Running Simulations ...")
for (config, filename) in zip(config_list, filename_list)
    model = initialize_model((10, 10), config)
    agent_df, _ = Agents.run!(
        model, agent_step!, 3000, adata=[:pos, :culture], 
        replicates=300, when=0:10:3000, parallel=true, obtainer=deepcopy
    )
    prepare_data!(agent_df, filename)
    Feather.write(joinpath("data", filename * ".feather"), agent_df)
    ProgressMeter.next!(p)
end

run_random(steps=3000, replicates=300, by=10, rnd_seed=0, write=true)

##
