#  Copyright 2014, Vincent Leclere, Francois Pacaud and Henri Gerard
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at http://mozilla.org/MPL/2.0/.
#############################################################################
# Model and solve the One-Step One Alea problem in different settings
# - used to compute the optimal control (in forward phase / simulation)
# - used to compute the cuts in the Backward phase
#############################################################################

using JuMP
using SDDP

"""
Solve the Bellman equation at time t starting at state x under alea xi
with the current evaluation of Vt+1

The function solve
min_u current_cost(t,x,u,xi) + current_Bellman_Value_{t+1}(dynamic(t,x,u,xi))
and can return the optimal control and a subgradient of the value of the
problem with respect to the initial state x


Parameters:
- model (SPmodel)
    the stochastic problem we want to optimize

- param (SDDPparameters)
    the parameters of the SDDP algorithm

- V (bellmanFunctions)
    the current estimation of Bellman's functions

- t (int)
    time step at which the problem is solved

- xt (Array{Float})
    current starting state

- xi (Array{float})
    current noise value

- returnOptNextStage (Bool)
    return the optimal state at t+1

- returnOptcontrol (Bool)
    return the optimal control

- returnSubgradient (Bool)
    return the subgradient

- returnCost (Bool)
    return the value of the problem

TODO: update returns
TODO: add types in function parameters

"""
function solve_one_step_one_alea(model, #::SDDP.LinearDynamicLinearCostSPmodel,
                                 param, #::SDDP.SDDPparameters,
                                 m::JuMP.Model, #::Vector{SDDP.PolyhedralFunction},
                                 t, #::Int64,
                                 xt, #::Vector{Float64},
                                 xi) #::Vector{Float64},
    # w = getVar(m, :w)
    # @addConstraint(m, m.ext[:w] .== xi)
    # @defVar(m, w[1:1] )
    # setValue(m, w, xi )
    # setValue(m, :w, xi)
    # chgConstrRHS(m, state_constraint, xt)
    # @addConstraint(m, state_constraint, x .== xt)

    status = solve(m)
    solved = (string(status) == "Optimal")

    if solved
        optimalControl = getValue(u)
        # Return object storing results:
        result = SDDP.NextStep(
                          [model.dynamics(xt, optimalControl, xi)],
                          optimalControl,
                          getDual(state_constraint),
                          getObjectiveValue(m))
    else
        # If no solution is found, then return nothing
        result = nothing
    end

    return solved, result
end
