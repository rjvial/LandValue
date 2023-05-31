using LandValue, NonconvexBayesian, NonconvexIpopt, NonconvexNLopt, Distributions


function ajustaPrecioReserva(valorMercado_lotes::Float64, valorInmobiliario::Float64, prob_ventaValorMercado::Float64, prob_ventaValorInmobiliario::Float64)
    #Esta función ajusta los parámetros α y λ de una distribución Weibull del precio de reserva r de manera que:
    # prob(r < valorMercado) = prob_ventaValorMercado y prob(r < valorInmobiliario) = prob_ventaValorInmobiliario

    prob_lb = prob_ventaValorMercado
    prob_ub = prob_ventaValorInmobiliario
    p_lb = valorMercado_lotes
    δ = p_lb * 0.9
    p_ub = valorInmobiliario
    α = log( log(1 - prob_lb) / log(1 - prob_ub) ) / log( (p_lb - δ) / (p_ub - δ) )
    λ = (p_ub - δ) / exp( log(log(1/(1 - prob_ub))) / α )
    return α, λ
end
function ajustaPrecioReserva(valorMercado_lotes::Vector{Float64}, valorInmobiliario_combis::Vector{Float64}, C::Matrix{Int64}, prob_ventaValorMercado, prob_ventaValorInmobiliario)
    #Esta versión acepta los vectores valorMercado_lotes y valorInmobiliario_combis además de la matriz de combinaciones C
    
    numLotes = length(valorMercado_lotes)
    α_vec = zeros(numLotes,1)
    λ_vec = zeros(numLotes,1)
    for k = 1:numLotes
        flag = C[:,k]
        valorInmobiliario_vec = valorInmobiliario_combis[ flag .== 1] ./ sum(C[flag .== 1,:], dims=2)
        valorInmobiliario = sum(valorInmobiliario_vec) / length(valorInmobiliario_vec)
        α_vec[k], λ_vec[k] = ajustaPrecioReserva(valorMercado_lotes[k], valorInmobiliario, prob_ventaValorMercado, prob_ventaValorInmobiliario)
    end
    return α_vec, λ_vec
end



function f(x::AbstractVector, α_vec, λ_vec, valorMercado_lotes, valorInmobiliario_combis, C) 
    numCombis, numLotes = size(C)
    δ_vec = valorMercado_lotes .* 0.9

    prob_vec = [x[i] - δ_vec[i] < 0 ? 0 : 1 - exp(-((x[i] - δ_vec[i]) / λ_vec[i])^α_vec[i]) for i = 1:numLotes]

    utilEsp = sum(
        # expected utility for a single combination
        (valorInmobiliario_combis[k] - sum([C[k,i] * x[i] for i=1:numLotes])) * 
        prod([C[k,i] == 1 ? prob_vec[i] : 1 - prob_vec[i] for i=1:numLotes])
        
        # loop over all combinations
        for k=1:numCombis
    )

    return -utilEsp
end

function g(x::AbstractVector, α_vec, λ_vec, valorMercado_lotes, C, minProb) #Restricción para asegurar una probabilidad mínima de éxito
    numCombis, numLotes = size(C)
    δ_vec = valorMercado_lotes .* 0.9

    prob_vec = [x[k] - δ_vec[k] < 0 ? 0 : 1 - exp(-((x[k] - δ_vec[k]) / λ_vec[k])^α_vec[k]) for k = 1:numLotes]

    # calculate the sum of the product of probabilities for each combination
    probCombis = sum(
        # calculate the product of probabilities for a single combination
        prod(C[k,i] == 1 ? prob_vec[i] : 1 - prob_vec[i] for i=1:numLotes)
        
        # loop over all combinations
        for k=1:numCombis
    )

    return minProb - probCombis
end


Ad = [0 0 0 1 1;
      0 0 1 1 0;
      0 1 0 1 0;
      1 1 1 0 1;
      1 0 0 1 0]

minProb = 0.8

graphMod.graphPlot(Ad)
         
numLotes = size(Ad,2)
valorMercado_lotes = vec(ones(numLotes,1) .* 38888.)

C = graphMod.node_combis(Ad, flag_mat = true) #matriz de Combinaciones de lotes

prob_compraValorMercado = .1
prob_compraValorInmobiliario = .9

valorPropietario_combis = sum(C, dims=2) .* (1.02.^(sum(C, dims=2))*45000.) #valor de los combis para los Propietarios
valorPropietario_combis[ sum(C, dims=2) .== 1 ] .= (38888. + 45000.) / 2
valorPropietario_combis = vec(valorPropietario_combis)
α_vec, λ_vec = ajustaPrecioReserva(valorMercado_lotes, valorPropietario_combis, C, prob_compraValorMercado, prob_compraValorInmobiliario)

valorInmobiliario_combis = sum(C, dims=2) .* (1.02.^(sum(C, dims=2))*45000.) #valor de los combis para el Inmobiliario
valorInmobiliario_combis[ sum(C, dims=2) .== 1 ] .= 38888.
valorInmobiliario_combis = vec(valorInmobiliario_combis)

lb_lotes = valorMercado_lotes
ub_lotes = 3 .* valorMercado_lotes


m = NonconvexBayesian.Model()
# set_objective!(m, x -> f(x, mu, sigma, C))
set_objective!(m, x -> f(x, α_vec, λ_vec, valorMercado_lotes, valorInmobiliario_combis, C))
addvar!(m, lb_lotes, ub_lotes)
# add_ineq_constraint!(m, x -> g(x, mu, sigma, valorInmobiliario_combis, C))
add_ineq_constraint!(m, x -> g(x, α_vec, λ_vec, valorMercado_lotes, C, minProb))

alg = BayesOptAlg(IpoptAlg())
options = BayesOptOptions(
    sub_options = IpoptOptions(print_level = 0), maxiter = 10, ctol = 1e-4,
    ninit = 2, initialize = true, postoptimize = false, fit_prior = true,)
r = optimize(m, alg, lb_lotes, options = options);
fopt = -r.minimum
xopt = r.minimizer

# numCombis, numLotes = size(C)
# prob_lotes = [Distributions.cdf(Distributions.LogNormal(mu[i], sigma[i]), xopt[i]) for i = 1:numLotes]

# # Compute the probability of each combination
# prob_combis = [prod( C[k,i] == 1 ? prob_lotes[i] : 1 - prob_lotes[i] for i in 1:numLotes ) for k in 1:numCombis]
