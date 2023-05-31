using NonconvexBayesian, NonconvexIpopt, NonconvexNLopt, Distributions
# Este caso asume multiples etapas de ofertas

# function fs(x::AbstractVector, δ, p_lb, p_ub, prob_lb, prob_ub, T)
#     # Sin Aprendizaje
#     α = log( log(1 - prob_lb) / log(1 - prob_ub) ) / log( (p_lb - δ) / (p_ub - δ) )
#     λ = (p_ub - δ) / exp( log(log(1/(1 - prob_ub))) / α )
#     utilEsp = 0
#     for t = 1:T
        
#         if t == 1            
#             prob = x[1] - δ < 0 ? 0 : 1 - exp(-((x[1] - δ) / λ)^α)
#             util_t = (p_ub - x[1]) * prob
#         else
#             util_t = (p_ub - x[t])
#             for k = 1:t-1
#                 prob_k = x[k] - δ < 0 ? 0 : 1 - exp(-((x[k] - δ) / λ)^α)
#                 util_t = util_t * (1 - prob_k)
#             end
#             prob_t = x[t] - δ < 0 ? 0 : 1 - exp(-((x[t] - δ) / λ)^α)
#             util_t = util_t * prob_t
#         end
#         utilEsp = utilEsp + util_t

#     end
#     return -utilEsp
# end


function fc(x::AbstractVector, δ, p_lb, p_ub, prob_lb, prob_ub, T)
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


g(x::AbstractVector, T) = -x[1]


δ = 35000.
p_ub = 45000.
p_lb = δ + (p_ub - δ) * .1

prob_lb = .10
prob_ub = .90



alg = BayesOptAlg(IpoptAlg())
options = BayesOptOptions(
    sub_options = IpoptOptions(print_level = 0), maxiter = 10, ctol = 1e-4,
    ninit = 2, initialize = true, postoptimize = false, fit_prior = true,
)


T = 3 # numero de ofertas que se puede hacer
mc = NonconvexBayesian.Model()
pos = [1/(T-1)*(i-1) for i=1:T]
x_lb = [δ for t=1:T]
x_ub = [p_ub for t=1:T]
initSol = x_lb
set_objective!(mc, x -> fc(x, δ, p_lb, p_ub, prob_lb, prob_ub, T))
addvar!(mc, x_lb, x_ub)
add_ineq_constraint!(mc, x -> g(x, T))
rc = optimize(mc, alg, initSol , options = options);
fopt_c = -rc.minimum
xopt_c = rc.minimizer
