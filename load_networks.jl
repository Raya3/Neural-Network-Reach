using MAT, LinearAlgebra
include("nnet.jl")


# Evaluate network. Takes care of normalizing inputs and un-normalizing outputs
function eval_net(input, weights, net_dict, copies::Int64)
	copies == 0 ? (return input) : nothing
	Aᵢₙ, bᵢₙ = net_dict["input_norm_map"]
	Aₒᵤₜ, bₒᵤₜ = net_dict["output_unnorm_map"]
	NN_out = vcat(Aᵢₙ*input + bᵢₙ, [1.])
    for layer = 1:length(weights)-1
        NN_out = max.(0, weights[layer]*NN_out)
    end
    output = Aₒᵤₜ*weights[end]*NN_out + bₒᵤₜ
    return eval_net(output, weights, net_dict, copies-1)
end

bound_r(a,b) = (b-a)*(rand()-1) + b # Generates a uniformly random number on [a,b]

# NN with input in, output out, hidden dim hdim, and hidden layers layers.
function random_net(in_d, out_d, hdim, layers)
	Weights = Vector{Array{Float64,2}}(undef,layers)
	Weights[1] = sqrt(2/515)*(2*rand(hdim, in_d) - rand(hdim, in_d))
	for i in 2:layers-1
		Weights[i] = sqrt(2/515)*(2*rand(hdim,hdim) - rand(hdim,hdim)) # Kaiming Initialization
	end
	Weights[end] = sqrt(2/515)*(2*rand(out_d, hdim) - rand(out_d, hdim))
	return Weights
end


# Load nnet network #
# filename = "ACASXU_experimental_v2a_1_1.nnet"
function nnet_load(filename)
	nnet = NNet(filename)
	weights = Vector{Array{Float64,2}}(undef, nnet.numLayers)
	for i in 1:(nnet.numLayers-1)
		weights[i] = vcat(hcat(nnet.weights[i], nnet.biases[i]), reshape(zeros(1+nnet.layerSizes[i]),1,:))
		weights[i][end,end] = 1
	end
	# last layer weight shouldn't carry forward the bias term. i.e. augmented but with last row removed
	weights[end] = hcat(nnet.weights[end], nnet.biases[end])

	# make net_dict
	σᵢ = Diagonal(nnet.ranges[1:end-1])
	μᵢ = nnet.means[1:end-1]
	σₒ = nnet.ranges[end]*Matrix{Float64}(I, nnet.inputSize, nnet.inputSize)
	μₒ = nnet.means[end]*ones(nnet.outputSize)

	net_dict = Dict()
	net_dict["num_layers"] = nnet.numLayers
	net_dict["layer_sizes"] = nnet.layerSizes
	net_dict["input_size"] = nnet.inputSize 
	net_dict["output_size"] = nnet.outputSize
	net_dict["input_norm_map"] = (inv(σᵢ), -inv(σᵢ)*μᵢ)
	net_dict["output_unnorm_map"] = (σₒ, μₒ) 

	return weights, nnet, net_dict
end


# Load ACAS Networks #
function acas_net_nnet(a::Int64, b::Int64)
	filename = string("models/ACAS_nnet/ACASXU_experimental_v2a_", a, "_", b, ".nnet")
	return nnet_load(filename)
end


# Load Pendulum Networks #
function pendulum_net(filename::String, copies::Int64)

	model = matread(filename)
	num_layers = length(model["weights"])
	layer_sizes = vcat(size(model["weights"][1], 2), [length(model["biases"][i]) for i in 1:num_layers])

	# make net_dict
	σᵢ = Float64.(Diagonal(vec(model["X_std"])))
	μᵢ = Float64.(vec(model["X_mean"]))
	σₒ = Float64.(Diagonal(vec(model["Y_std"])))
	μₒ = Float64.(vec(model["Y_mean"]))
	Aᵢₙ, bᵢₙ = inv(σᵢ), -inv(σᵢ)*μᵢ
	Aₒᵤₜ, bₒᵤₜ = σₒ, μₒ

	net_dict = Dict()
	net_dict["num_layers"] = num_layers
	net_dict["layer_sizes"] = layer_sizes
	net_dict["input_size"] = layer_sizes[1]
	net_dict["output_size"] = layer_sizes[end]
	net_dict["input_norm_map"] = (Aᵢₙ, bᵢₙ)
	net_dict["output_unnorm_map"] = (Aₒᵤₜ, bₒᵤₜ) 


	w = Vector{Array{Float64,2}}(undef, num_layers)
	for i in 1:(num_layers-1)
		w[i] = vcat(hcat(model["weights"][i], vec(model["biases"][i])), reshape(zeros(1+layer_sizes[i]),1,:))
		w[i][end,end] = 1
	end
	w[end] = hcat(model["weights"][end], vec(model["biases"][end]))
	
	weights = Vector{Array{Float64,2}}(undef, copies*num_layers - (copies-1))
	merged_layers = [c*num_layers - (c-1) for c in 1:copies]
	w_idx = 1
	for k in 1:length(weights)
		if k == 1
			weights[k] = w[1]
			w_idx += 1
		elseif k == length(weights)
			weights[k] = w[end]
		elseif k in merged_layers
			w̄ₒ = vcat(w[end], reshape(zeros(1+layer_sizes[end-1]),1,:))
			w̄ₒ[end,end] = 1
			Āₒ = vcat(hcat(Aₒᵤₜ, bₒᵤₜ), reshape(zeros(1+layer_sizes[end]),1,:))
			Āₒ[end,end] = 1
			Āᵢ = vcat(hcat(Aᵢₙ, bᵢₙ), reshape(zeros(1+layer_sizes[1]),1,:))
			Āᵢ[end,end] = 1
			
			weights[k] = w[1]*Āᵢ*Āₒ*w̄ₒ
			w_idx = 2
		else
			weights[k] = w[w_idx]
			w_idx += 1
		end
	end

	return weights, net_dict
end


# Load networks given as .mat files that were obtained from extract_onnx_params.py
function load_test_small()
	B0 = [1.5; 1.5]
	W2 = [3.0 3.0]
	B2 = [3.5]
	W0 = [1.0; 1.0]
	B1 = [2.5; 2.5]
	W1 = [2.0 2.0; 2.0 2.0]

	# Construct augmented weights. 
	weights = Vector{Array{Float64,2}}(undef, 3)
	weights[1] = vcat(hcat(W0, B0), reshape(zeros(size(W0,2)+1),1,:))
	weights[1][end,end] = 1

	weights[2] = vcat(hcat(W1, B1), reshape(zeros(size(W1,2)+1),1,:))
	weights[2][end,end] = 1

	# last layer weight shouldn't carry forward the bias term. i.e. augmented but with last row removed
	weights[end] = hcat(W2, B2)

	
	return weights
end


function load_test_tiny()
	W0 = [1.0]
	B0 = [0.0]
	W1 = [1.0]
	B1 = [0.0]

	# Construct augmented weights. 
	weights = Vector{Array{Float64,2}}(undef, 2)
	weights[1] = [1.0 0.0; 0.0 1.0]
	weights[2] = [1.0 0.0]

	return weights
end


# Load networks given as .mat files that were obtained from extract_onnx_params.py
function load_mat_onnx_test_acas(filename)
	vars = matread(string("Neural-Network-Reach/", filename))
	weight = r"MatMul_W"
	bias = r"Add_B"

	# Determine number of layers
	num_layers = 0
	for key in keys(vars)
		occursin(weight, key) ? num_layers += 1 : nothing
	end

	# Construct augmented weights. 
	weights = Vector{Array{Float64,2}}(undef, num_layers)
	for i in 1:(num_layers-1)
		w = vars[string("Operation_", i, "_MatMul_W")]
		b = vec(vars[string("Operation_", i, "_Add_B")])

		weights[i] = vcat(hcat(w, b), reshape(zeros(size(w,2)+1),1,:))
		weights[i][end,end] = 1
	end

	# last layer weight shouldn't carry forward the bias term. i.e. augmented but with last row removed
	w = vars[string("linear_", num_layers, "_MatMul_W")]
	b = vec(vars[string("linear_", num_layers, "_Add_B")])
	weights[end] = hcat(w, b)
	return weights
end


# Load networks given as .mat files that were obtained from extract_onnx_params.py
function load_mat_onnx_acas(filename)
	vars = matread(string("Neural-Network-Reach/", filename))
	weight = r"MatMul_W"
	bias = r"Add_B"

	# Determine number of layers
	num_layers = 0
	for key in keys(vars)
		occursin(weight, key) ? num_layers += 1 : nothing
	end

	# Construct augmented weights. 
	weights = Vector{Array{Float64,2}}(undef, num_layers)
	for i in 1:(num_layers-1)
		w = vars[string("Operation_", i, "_MatMul_W")]
		b = vec(vars[string("Operation_", i, "_Add_B")])

		weights[i] = vcat(hcat(w, b), reshape(zeros(size(w,2)+1),1,:))
		weights[i][end,end] = 1
	end

	# last layer weight shouldn't carry forward the bias term. i.e. augmented but with last row removed
	w = vars[string("linear_", num_layers, "_MatMul_W")]
	b = vec(vars[string("linear_", num_layers, "_Add_B")])
	weights[end] = hcat(w, b)
	return weights
end


function load_mat_onnx_mnist(filename)
	vars = matread(string("Neural-Network-Reach/", filename))
	weight = r"weight"
	bias = r"bias"

	# Determine number of layers
	num_layers = 0
	for key in keys(vars)
		occursin(weight, key) ? num_layers += 1 : nothing
	end

	# Construct augmented weights. 
	weights = Vector{Array{Float64,2}}(undef, num_layers)
	for (i,j) in enumerate(0:2:2*(num_layers-2))
		w = vars[string("layers.", j, ".weight")]'
		b = vec(vars[string("layers.", j, ".bias")])
		weights[i] = vcat(hcat(w, b), reshape(zeros(size(w,2)+1),1,:))
		weights[i][end,end] = 1
	end

	# last layer weight shouldn't carry forward the bias term. i.e. augmented but with last row removed
	w = vars[string("layers.", 2*(num_layers-1), ".weight")]'
	b = vec(vars[string("layers.", 2*(num_layers-1), ".bias")])
	weights[end] = hcat(w, b)
	return weights
end