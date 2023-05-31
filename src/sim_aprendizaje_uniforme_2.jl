using NonconvexBayesian, NonconvexIpopt, NonconvexNLopt, Distributions, Plots
# Este caso asume que aprendizaje con precio de reserva distribuido uniforme


function fc(x::AbstractVector, p_inmob, p_lb, p_ub, T)
    # Con Aprendizaje
    lb = p_lb
    ub = p_ub
    utilEsp = 0
    for t = 1:T
        if t == 1
            prob_t = (x[t] - lb) / (ub - lb)
            util_t = (p_inmob - x[t]) * prob_t
        else
            util_t = (p_inmob - x[t])
            for k = 1:t-1
                prob_k = k == 1 ? (x[k] - lb) / (ub - lb) : (x[k] - x[k-1]) / (ub - x[k-1])
                util_t = util_t * (1 - prob_k)
            end
            prob_t = (x[t] - x[t-1]) / (ub - x[t-1])
            util_t = util_t * prob_t
        end
        desc = t == 1 ? 1 : 1^((t-1)/(T-1))
        utilEsp = utilEsp + util_t * desc
    end
    return -utilEsp
end


function g(x::AbstractVector, p_inmob, p_lb, p_ub, T, minProb) 
    lb = p_lb
    ub = p_ub    
    prob = 0
    for t = 1:T
        prob_t = (x[t] - lb) / (ub - lb)
        prob_t0 = 1
        if t >= 2
            for k = 1:t-1
                prob_k = (p_inmob - x[k]) / (ub - lb)
                prob_t0 = prob_t0 * prob_k
            end
        end
        prob_t = prob_t * prob_t0
        prob = prob + prob_t
    end
    return minProb - prob
end

minProb = .7
T = 3 # numero de ofertas que se puede hacer
p_lb = 30000; prob_lb =  0
p_inmob = 45000; prob_inmob = 0.9
p_ub = p_inmob / prob_inmob
x_lb = vec(p_lb .* ones(T,1))
x_ub = vec(p_ub .* ones(T,1))

alg = BayesOptAlg(IpoptAlg())
options = BayesOptOptions(
    sub_options = IpoptOptions(print_level = 0), maxiter = 10, ctol = 1e-4,
    ninit = 2, initialize = true, postoptimize = false, fit_prior = true,
)

mc = NonconvexBayesian.Model()
set_objective!(mc, x -> fc(x, p_inmob, p_lb, p_ub, T))
addvar!(mc, x_lb, x_ub)
add_ineq_constraint!(mc, x -> g(x, p_inmob, p_lb, p_ub, T, minProb))
rc = optimize(mc, alg, x_lb, options = options);
fopt_c = -rc.minimum
xopt_c = rc.minimizer


x_user = [90, 150, 170]

num_sim = 1000
vec_res_price = rand(Distributions.Uniform(p_lb, p_ub), num_sim)
vec_util_opt = zeros(size(vec_res_price))
vec_util_user = zeros(size(vec_res_price))
for i in eachindex(vec_res_price)
    if vec_res_price[i] <= maximum(xopt_c)
        pos_i = findfirst(vec_res_price[i] .<= xopt_c[:])
        vec_util_opt[i] = p_inmob - xopt_c[pos_i]
    end
    if vec_res_price[i] <= maximum(x_user)
        pos_i = findfirst(vec_res_price[i] .<= x_user[:])
        vec_util_user[i] = p_inmob - x_user[pos_i]
    end
end
util_prom_user = sum(vec_util_user)/num_sim
util_prom_opt = sum(vec_util_opt)/num_sim
prob_user = sum(vec_util_user .> 0)/num_sim
prob_opt = sum(vec_util_opt .> 0)/num_sim

display("1) Usuario: Utilidad Promedio: " * string(util_prom_user) * " ; Probabilidad Promedio " * string(prob_user))
display("2) Óptimo: Utilidad Promedio: " * string(util_prom_opt) * " ; Probabilidad Promedio " * string(prob_opt))
