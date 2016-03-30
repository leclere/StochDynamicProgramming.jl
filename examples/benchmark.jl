#  Copyright 2015, Vincent Leclere, Francois Pacaud and Henri Gerard
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at http://mozilla.org/MPL/2.0/.
#############################################################################
# Benchmark SDDP algorithm upon damsvalley example
# This benchmark includes:
# - comparison of execution time
# - gap between the SDDP solution and the deterministic solution
#############################################################################

srand(2713)
push!(LOAD_PATH, "../src")

using StochDynamicProgramming, JuMP
using Clp

SOLVER = ClpSolver()
#= const SOLVER = CplexSolver(CPX_PARAM_SIMDISPLAY=0, CPX_PARAM_THREADS=4) =#

const N_STAGES = 10

# COST:
const COST = -66*2.7*(1 + .5*(rand(N_STAGES) - .5))

# Define dynamic of the dam:
function dynamic(t, x, u, w)
    return [x[1] - u[1] - u[3] + w[1], x[2] - u[2] - u[4] + u[1] + u[3]]
end

# Define cost corresponding to each timestep:
function cost_t(t, x, u, w)
    return COST[t] * (u[1] + u[2])
end

function final_cost(x)
	return 0.
end 


function constraints(t, x1, u, w)

    Bu = (x1[1]<=VOLUME_MAX)
    Bl = (x1[1]>=VOLUME_MIN)

    return Bu&Bl

end


"""Solve the problem with a solver, supposing the aleas are known
in advance."""
function solve_determinist_problem(model, scenario)
    m = Model(solver=SOLVER)


    @defVar(m,  model.xlim[1][1]  <= x1[1:(N_STAGES)]  <= model.xlim[1][2])
    @defVar(m,  model.xlim[2][1]  <= x2[1:(N_STAGES)]  <= model.xlim[2][2])
    @defVar(m,  model.ulim[1][1] <= u1[1:N_STAGES-1]  <= model.ulim[1][2])
    @defVar(m,  model.ulim[2][1] <= u2[1:N_STAGES-1]  <= model.ulim[2][2])

    @setObjective(m, Min, sum{COST[i]*(u1[i] + u2[i]), i = 1:N_STAGES-1})

    for i in 1:N_STAGES-1
        @addConstraint(m, x1[i+1] - x1[i] + u1[i] - scenario[i] == 0)
        @addConstraint(m, x2[i+1] - x2[i] + u2[i] - u1[i] == 0)
    end

    @addConstraint(m, x1[1] == model.initialState[1])
    @addConstraint(m, x2[1] == model.initialState[2])

    status = solve(m)
    return getObjectiveValue(m)
end


"""Build aleas probabilities for each month."""
function build_aleas()
    W_MAX = round(Int, .5/7. * 100)
    W_MIN = 0
    DW = 1
    # Define aleas' space:
    N_ALEAS = Int(round(Int, (W_MAX - W_MIN) / DW + 1))
    ALEAS = linspace(W_MIN, W_MAX, N_ALEAS)

    aleas = zeros(N_ALEAS, N_STAGES)

    # take into account seasonality effects:
    unorm_prob = linspace(1, N_ALEAS, N_ALEAS)
    proba1 = unorm_prob / sum(unorm_prob)
    proba2 = proba1[N_ALEAS:-1:1]

    for t in 1:N_STAGES
        aleas[:, t] = (1 - sin(pi*t/N_STAGES)) * proba1 + sin(pi*t/N_STAGES) * proba2
    end
    return aleas
end


"""Build an admissible scenario for water inflow."""
function build_scenarios(n_scenarios::Int64, probabilities)
    scenarios = zeros(n_scenarios, N_STAGES)

    for scen in 1:n_scenarios
        for t in 1:N_STAGES
            Pcum = cumsum(probabilities[:, t])

            n_random = rand()
            prob = findfirst(x -> x > n_random, Pcum)
            scenarios[scen, t] = prob
        end
    end
    return scenarios
end


"""Build probability distribution at each timestep.

Return a Vector{NoiseLaw}"""
function generate_probability_laws(n_scenarios)
    aleas = build_scenarios(n_scenarios, build_aleas())

    laws = Vector{NoiseLaw}(N_STAGES)

    # uniform probabilities:
    proba = 1/n_scenarios*ones(n_scenarios)

    for t=1:N_STAGES
        laws[t] = NoiseLaw(aleas[:, t], proba)
    end

    return laws
end


function init_problem_sdp_HD(model)

    x0 = model.initialState
    aleas = generate_probability_laws(10)

    x_bounds = model.xlim
    u_bounds = model.ulim

    # Constants:
    VOLUME_MAX = 100
    VOLUME_MIN = 0
    CONTROL_MAX = round(Int, .4/7. * VOLUME_MAX) + 1
    CONTROL_MIN = 0


    N_CONTROLS = 4
    N_STATES = 2
    N_NOISES = 1
    infoStruct = "HD"

    stateSteps = [1, 1]
    controlSteps = [1, 1, 1, 1]
    stateVariablesSizes = [(VOLUME_MAX-VOLUME_MIN)+1]
    controlVariablesSizes = [(CONTROL_MAX-CONTROL_MIN)+1, (VOLUME_MAX)+1]
    totalStateSpaceSize = stateVariablesSizes[1]
    totalControlSpaceSize = controlVariablesSizes[1]*controlVariablesSizes[2]
    monteCarloSize = 10

    model = StochDynProgModel(N_STAGES-1,
                    N_CONTROLS,
                    N_STATES,
                    N_NOISES,
                    x_bounds,
                    u_bounds,
                    x0,
                    cost_t,
                    final_cost, 
                    dynamic,
                    constraints,
                    aleas)

    params = SDPparameters(model, stateSteps, controlSteps, 
                            monteCarloSize, infoStruct)


    return model, params
end


"""Instantiate the problem."""
function init_problem()

    N_SCENARIOS = 10

    x0 = [50, 50]
    aleas = generate_probability_laws(N_SCENARIOS)

    # Constants:
    VOLUME_MAX = 100
    VOLUME_MIN = 0
    CONTROL_MAX = round(Int, .4/7. * VOLUME_MAX) + 1
    CONTROL_MIN = 0



    x_bounds = [(VOLUME_MIN, VOLUME_MAX), (VOLUME_MIN, VOLUME_MAX)]
    u_bounds = [(CONTROL_MIN, CONTROL_MAX), (CONTROL_MIN, CONTROL_MAX), (0, Inf), (0, Inf)]

    model = LinearDynamicLinearCostSPmodel(N_STAGES,
                                                u_bounds,
                                                x0,
                                                cost_t,
                                                dynamic,
                                                aleas)

    set_state_bounds(model, x_bounds)


    EPSILON = .05
    MAX_ITER = 20
    solver = SOLVER
    params = SDDPparameters(solver, N_SCENARIOS, EPSILON, MAX_ITER)

    return model, params
end


"""Benchmark SDDP."""
function benchmark_sddp(display=false)
    model, params = init_problem()

	# Launch a first start to compile solve_SDDP
	params.maxItNumber = 2
	V, pbs = solve_SDDP(model, params, 0)
	params.maxItNumber = 20
    # Launch benchmark
    println("Launch SDDP ...")
    tic()
    V, pbs = solve_SDDP(model, params, 0)
    texec = toq()
    println("Time to solve SDDP: ", texec, "s")

    # Test results upon 100 assessment scenarios:
    n_assessments = 100
    aleas = simulate_scenarios(model.noises,
                              (model.stageNumber,
                               n_assessments,
                               model.dimNoises))

    params.forwardPassNumber = n_assessments

    tic()
    costs_sddp, stocks = forward_simulations(model, params, V, pbs, aleas)
    texec = toq()
    println("Time to perform simulation: ", texec, "s")

    # Get costs with deterministic solution:
    println("Compute deterministic solution ...")
    costs_det = zeros(n_assessments)
    for n in 1:n_assessments
        costs_det[n] = solve_determinist_problem(model, aleas[:, n, :])
    end

    println("SDDP cost: \t", mean(costs_sddp))
    println("Deterministic cost: \t", mean(costs_det))
    println("Gap: \t", mean(costs_det)/mean(costs_sddp))
    return stocks, V
end


"""Benchmark SDP."""
function benchmark_sdp(display=false)

	N_STAGES = 5
	TF = N_STAGES
    # Capacity of dams:
    VOLUME_MAX = 50.
    VOLUME_MIN = 0

    # Specify the maximum flow of turbines:
    CONTROL_MAX = 10
    CONTROL_MIN = 0

    # Some statistics about aleas (water inflow):
    W_MAX = 5
    W_MIN = 0
    DW = 1

    T0 = 1

    # Define aleas' space:
    N_ALEAS = Int(round(Int, (W_MAX - W_MIN) / DW + 1))
    ALEAS = linspace(W_MIN, W_MAX, N_ALEAS);

    N_CONTROLS = 2;
    N_STATES = 2;
    N_NOISES = 1;

    infoStruct = "HD"

    COST = 66*2.7*(1 + .5*(rand(TF) - .5));

    #= # Define dynamic of the dam: =#
    #= function dynamic(t, x, u, w, xf) =#
		#= xf[1] = x[1] + u[1] + w[1] - u[2] =#
		#= xf[2] =  x[2] - u[1] =#
    #= end =#

    # Define dynamic of the dam:
    function dynamic(t, x, u, w)
        return [x[1] + u[1] + w[1] - u[2], x[2] - u[1]]
    end

    # Define cost corresponding to each timestep:
    function cost_t(t, x, u, w)
        return COST[t] * (u[1])
    end

    function constraints(t, x, u, w)
        return (x[1]<=VOLUME_MAX)&(x[1]>=VOLUME_MIN)&(x[2]<=VOLUME_MAX)&(x[2]>=VOLUME_MIN)
    end

    function finalCostFunction(x)
        return 0.
    end

    """Build admissible scenarios for water inflow over the time horizon."""
    function build_scenarios(n_scenarios::Int64)
        scenarios = zeros(n_scenarios, TF)

        for scen in 1:n_scenarios
            scenarios[scen, :] = (W_MAX-W_MIN)*rand(TF)+W_MIN
        end
        return scenarios
    end

        """Build probability distribution at each timestep based on N scenarios.
    Return a Vector{NoiseLaw}"""
    function generate_probability_laws(N_STAGES, N_SCENARIOS)
        aleas = zeros(N_SCENARIOS, TF, 1)
        aleas[:, :, 1] = build_scenarios(N_SCENARIOS)

        laws = Vector{NoiseLaw}(N_STAGES)

        # uniform probabilities:
        proba = 1/N_SCENARIOS*ones(N_SCENARIOS)

        for t=1:N_STAGES
            aleas_t = reshape(aleas[:, t, :], N_SCENARIOS, 1)'
            laws[t] = NoiseLaw(aleas_t, proba)
        end

        return laws
    end

    N_SCENARIO = 5
    aleas = generate_probability_laws(TF, N_SCENARIO)

    x_bounds = [(VOLUME_MIN, VOLUME_MAX), (VOLUME_MIN, VOLUME_MAX)];
    u_bounds = [(CONTROL_MIN, CONTROL_MAX), (VOLUME_MIN, 10)];

    x0 = [20., 22.]

    modelSDP = StochDynProgModel(N_STAGES-1, N_CONTROLS,
                        N_STATES, N_NOISES,
                        x_bounds, u_bounds,
                        x0, cost_t,
                        finalCostFunction, dynamic,
                        constraints, aleas);

    stateSteps = [1,1];
    controlSteps = [1,1];
    monteCarloSize = 10;

    paramsSDP = StochDynamicProgramming.SDPparameters(modelSDP, stateSteps,
                                                     controlSteps,
                                                     monteCarloSize,
                                                     infoStruct);


	print("T*X*U*W :")
	println(paramsSDP.totalStateSpaceSize*paramsSDP.totalControlSpaceSize)
	tic()
	V_sdp = sdp_optimize(modelSDP, paramsSDP,false);
	time = toq()
	println("SDP execution time: ", time, " s")

end

# SDDP benchmark: 
if ARGS[1] == "SDDP"
	benchmark_sddp()
elseif ARGS[1] == "DP"
	benchmark_sdp()
end

