using Optimization, OptimizationOptimJL, ForwardDiff, Plots


function fo_bbo(x, param)
    δ = param[1]
    p_lb = param[2]
    p_ub = param[3]
    prob_lb = param[4]
    prob_ub = param[5]
    T = Int(param[6])
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

    return -utilEsp
end

δ = 90.
p_ub = 200.
p_lb = δ + (p_ub - δ) * .1
prob_lb = .10
prob_ub = .90
T = 5 # numero de ofertas que se puede hacer
param = [δ, p_lb, p_ub, prob_lb, prob_ub, T]


f = OptimizationFunction(fo_bbo, Optimization.AutoForwardDiff())
x0 = [δ for t=1:T]
prob = OptimizationProblem(f, x0, param)
sol = solve(prob, BFGS())




#plot(xopt)