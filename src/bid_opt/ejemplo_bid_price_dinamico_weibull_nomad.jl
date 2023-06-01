using NOMAD, Plots, Interpolations



function fo_nomad(x, δ, p_lb, p_ub, prob_lb, prob_ub, T)

    # Con Aprendizaje
    utilEsp = 0
    for t = 1:T
        
        if t == 1
            δ_1 = δ
            p_lb_1 = p_lb
            p_ub_1 = p_ub
            prob_lb_1 = prob_lb
            prob_ub_1 = prob_ub
            α_1 = log( log(1 - prob_lb_1) / log(1 - prob_ub_1) ) / log( (p_lb_1 - δ_1) / (p_ub_1 - δ_1) )
            λ_1 = (p_ub_1 - δ_1) / exp( log(log(1/(1 - prob_ub_1))) / α_1 )
            prob_1 = x[1] - δ_1 < 0 ? 0 : 1 - exp(-((x[1] - δ_1) / λ_1)^α_1)
            util_t = (p_ub_1 - x[1]) * prob_1
        else
            util_t = (p_ub - x[t])
            for k = 1:t-1
                δ_k = k == 1 ? δ : x[k-1]
                p_lb_k = δ_k + (p_ub - δ_k) * .1
                p_ub_k = p_ub
                prob_lb_k = prob_lb
                prob_ub_k = prob_ub
                α_k = log( log(1 - prob_lb_k) / log(1 - prob_ub_k) ) / log( (p_lb_k - δ_k) / (p_ub_k - δ_k) )
                λ_k = (p_ub_k - δ_k) / exp( log(log(1 / (1 - prob_ub_k))) / α_k )
                prob_k = x[k] - δ_k < 0 ? 0 : 1 - exp(-((x[k] - δ_k) / λ_k)^α_k)
                util_t = util_t * (1 - prob_k)
            end
            δ_t = x[t-1]
            p_lb_t = δ_t + (p_ub - δ_t) * .1
            p_ub_t = p_ub
            prob_lb_t = prob_lb
            prob_ub_t = prob_ub
            α_t = log( log(1 - prob_lb_t) / log(1 - prob_ub_t) ) / log( (p_lb_t - δ_t) / (p_ub_t - δ_t) )
            λ_t = (p_ub_t - δ_t) / exp( log(log(1 / (1 - prob_ub_t))) / α_t )
            prob_t = x[t] - δ_t < 0 ? 0 : 1 - exp(-((x[t] - δ_t) / λ_t)^α_t)
            util_t = util_t * prob_t
        end
        utilEsp = utilEsp + util_t

    end

    constraints = []
    for t = 1:T-1
        constraints = push!(constraints, x[t]-x[t+1])
    end


    # Integración Función Objetivo con Restricciones
    bb_outputs = [-utilEsp; constraints]
    success = true
    count_eval = true

    return (success, count_eval, bb_outputs)
end

δ = 90.
p_ub = 200.
p_lb = δ + (p_ub - δ) * .1

prob_lb = .10
prob_ub = .90


T = 5 # numero de ofertas que se puede hacer

obj_nomad = x -> fo_nomad(x, δ, p_lb, p_ub, prob_lb, prob_ub, T)

lb = [δ for t=1:T]
ub = [p_ub for t=1:T]

num_inputs = length(lb); # Number of inputs of the blackbox. Is required to be > 0
num_outputs = (T-1) + 1; # Number of outputs of the blackbox. Is required to be > 0
output_types = vcat(["OBJ"], ["PB" for i in 1:T-1]); # "OBJ" objective value to be minimized, "PB" progressive barrier constraint, "EB" extreme barrier constraint
input_types = vcat(["I"], ["R" for i in 1:num_inputs-1]); # A vector containing String objects that define the types of inputs to be given to eval_bb (the order is important). "R" Real/Continuous, "B" Binary,"I" Integer

p = NOMAD.NomadProblem(num_inputs, num_outputs, output_types, obj_nomad; 
                input_types = input_types, 
                lower_bound = lb, 
                upper_bound = ub)


p.options.display_degree = 0 #0;
#p.options.max_bb_eval = MaxSteps; # Fix some options

# solve problem starting from the point
initSol = [δ+(p_ub-δ)/(T-1)*(i-1) for i=1:T]

result = NOMAD.solve(p, initSol);

fopt = result.bbo_best_feas[1]
xopt = result.x_best_feas

plot(xopt)