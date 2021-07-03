# TO RUN from home directory
# $ julia --project="Neural-Network-Reach/" Neural-Network-Reach/vnn_run.jl "vnncomp2021/benchmarks/test/test_tiny.onnx" "vnncomp2021/benchmarks/vnncomp2021/benchmarks/test/test_tiny.vnnlib" "Neural-Network-Reach/test/test_tiny_output.txt" 200
# $ julia --project="Neural-Network-Reach/" Neural-Network-Reach/vnn_run.jl "vnncomp2021/benchmarks/test/test_small.onnx" "vnncomp2021/benchmarks/vnncomp2021/benchmarks/test/test_small.vnnlib" "Neural-Network-Reach/test/test_small_output.txt" 200
# $ julia --project="Neural-Network-Reach/" Neural-Network-Reach/vnn_run.jl "vnncomp2021/benchmarks/test/test_sat.onnx" "vnncomp2021/benchmarks/vnncomp2021/benchmarks/test/test_prop.vnnlib" "Neural-Network-Reach/test/test_sat_output.txt" 200
# $ julia --project="Neural-Network-Reach/" Neural-Network-Reach/vnn_run.jl "vnncomp2021/benchmarks/test/test_unsat.onnx" "vnncomp2021/benchmarks/test/test_prop.vnnlib" "Neural-Network-Reach/test/test_unsat_output.txt" 10
# $ julia --project="Neural-Network-Reach/" Neural-Network-Reach/vnn_run.jl "vnncomp2021/benchmarks/acasxu/ACASXU_run2a_5_7_batch_2000.onnx" "vnncomp2021/benchmarks/acasxu/prop_3.vnnlib" "Neural-Network-Reach/acasxu/prop_3_output.txt" 200
# $ julia --project="Neural-Network-Reach/" Neural-Network-Reach/vnn_run.jl "vnncomp2021/benchmarks/mnistfc/mnist-net_256x2.onnx" "vnncomp2021/benchmarks/mnistfc/prop_0_0.03.vnnlib" "Neural-Network-Reach/mnistfc/prop_0_0.03.txt" 200
# $ julia --project="Neural-Network-Reach/" Neural-Network-Reach/vnn_run.jl "vnncomp2021/benchmarks/mnistfc/mnist-net_256x6.onnx" "vnncomp2021/benchmarks/mnistfc/prop_0_0.03.vnnlib" "Neural-Network-Reach/mnistfc/prop_0_0.03.txt" 20

include("reach.jl")
include("load_vnn.jl")


function solve_problem(weights, A_in, b_in, A_out, b_out, output_filename)
	try
		verification_res = "unknown"
		for i in 1:length(b_in)
			ap2input, ap2output, ap2map, ap2backward, verification_res = compute_reach(weights, A_in[i], b_in[i], A_out, b_out, verification=true)
			if verification_res == "violated"
				open(output_filename, "w") do io
			    write(io, verification_res)
				end
			   return nothing
			end
		end
		open(output_filename, "w") do io
	    write(io, verification_res)
		end
		return nothing

	catch y
		if isa(y, InterruptException)
			println("timeout")
			open(output_filename, "w") do io
		    write(io, "timeout")
			end
		else
			@show y
			open(output_filename, "w") do io
			println("unknown")
		    write(io, "unknown")
			end
		end
	end
   return nothing
end

macro timeout(expr, seconds=-1, cb=(tsk) -> Base.throwto(tsk, InterruptException()))
    quote
        tsk = @task $expr
        schedule(tsk)
        if $seconds > -1
            Timer((timer) -> $cb(tsk), $seconds)
        end
        return fetch(tsk)
    end
end



# Solve on small problem to compile functions
function small_compile()
	weights = random_net(3, 2, 3, 3) # (in_d, out_d, hdim, layers)
	Aᵢ = [1. 0.; -1. 0.; 0. 1.; 0. -1.; 1. 1.; -1. 1.; 1. -1.; -1. -1.]
	bᵢ = [5., 5., 5., 5., 8., 8., 8., 8.]
	Aₒ = [1. 0.; -1. 0.; 0. 1.; 0. -1.]
	bₒ = [101., -100., 101., -100.]
	ap2input, ap2output, ap2map, ap2backward, verification_res = compute_reach(weights, Aᵢ, bᵢ, [Aₒ], [bₒ], verification=true, verbose=false)
	return nothing
end

# Solve on small problem to compile functions
small_compile()

# Load in arguments
onnx_filename = ARGS[1]
mat_onnx_filename = string(onnx_filename[1:end-4], "mat")
vnnlib_filename = ARGS[2]
output_filename = ARGS[3]
time_limit = parse(Float64, ARGS[4])

prefix = "vnncomp2021/benchmarks/"
mat_filename = mat_onnx_filename[length(prefix)+1:end]
vnnlib_filename = vnnlib_filename[length(prefix)+1:end]

# Get network weights
if mat_filename == "test/test_tiny.mat" 
	weights = load_test_tiny()
elseif mat_filename == "test/test_small.mat"
	weights = load_test_small()
elseif mat_filename == "test/test_sat.mat" || mat_filename == "test/test_unsat.mat"
	weights = load_mat_onnx_test_acas(mat_filename)
elseif mat_filename[1:6] == "acasxu"
	weights = load_mat_onnx_acas(mat_filename)
elseif mat_filename[1:7] == "mnistfc"
	weights = load_mat_onnx_mnist(mat_filename)
else
	# skip benchmark
	println("Got unexpected ONNX filename!")
	@show mat_filename
	weights = nothing
end

A_in, b_in, A_out, b_out = get_constraints(vnnlib_filename)
@timeout solve_problem(weights, A_in, b_in, A_out, b_out, output_filename) time_limit