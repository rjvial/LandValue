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

function fs(x::AbstractVector, p_inmob, p_lb, p_ub, T)
    # Sin Aprendizaje
    lb = p_lb
    ub = p_ub    
    utilEsp = 0
    for t = 1:T
        prob_t = (x[t] - lb) / (ub - lb)
        util_t = (p_inmob - x[t])
        if t >= 2
            for k = 1:t-1
                prob_k = (p_inmob - x[k]) / (ub - lb)
                util_t = util_t * prob_k
            end
        end
        util_t = util_t * prob_t
        utilEsp = utilEsp + util_t
    end
    return -utilEsp
end

g(x::AbstractVector) = -x[1]

T = 1 # numero de ofertas que se puede hacer
p_lb = 35000; prob_lb =  0
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
add_ineq_constraint!(mc, x -> g(x))
rc = optimize(mc, alg, x_lb, options = options);
fopt_c = -rc.minimum
xopt_c = rc.minimizer

# ms = NonconvexBayesian.Model()
# set_objective!(ms, x -> fs(x, p_inmob, p_lb, p_ub, T))
# addvar!(ms, x_lb, x_ub)
# add_ineq_constraint!(ms, x -> g(x))
# rs = optimize(ms, alg, x_lb, options = options);
# fopt_s = -rs.minimum
# xopt_s = rs.minimizer
# x_user = xopt_s

x_user = [.85*p_inmob]

num_sim = 10000
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
display("Utilidad Promedio Usuario: " * string(util_prom_user))
display("Utilidad Promedio Optima: " * string(util_prom_opt))
display("Diferencia Porcentual: " * string(util_prom_user/util_prom_opt - 1))
