using LandValue, NonconvexBayesian, NonconvexIpopt, NonconvexNLopt, Distributions

function ajustaPrecioReserva(valorMercado_lotes::Float64, valorInmobiliario::Float64, prob_ventaValorMercado::Float64, prob_ventaValorInmobiliario::Float64)
      #Esta función ajusta los parámetros mu y sigma de una distribución LogNormal del precio de reserva r de manera que:
      # prob(r < valorMercado) = prob_ventaValorMercado y prob(r < valorInmobiliario) = prob_ventaValorInmobiliario
  
      function f(x::AbstractVector, valorMercado, valorInmobiliario, prob_ventaValorMercado, prob_ventaValorInmobiliario)
  
          mu = x[1]
          sigma = x[2]
  
          prob_valorMercado = Distributions.cdf(Distributions.LogNormal(mu, sigma), valorMercado)
          prob_valorInmobiliario = Distributions.cdf(Distributions.LogNormal(mu, sigma), valorInmobiliario)
      
          dif_cuad = (prob_valorMercado-prob_ventaValorMercado)^2 + (prob_valorInmobiliario - prob_ventaValorInmobiliario)^2
  
          return dif_cuad
      end
  
      g(x::AbstractVector) = -x[1]
  
      lb_param = [0, 0]
      ub_param = [30, 30]
  
      m = NonconvexBayesian.Model()
      set_objective!(m, x -> f(x, valorMercado_lotes, valorInmobiliario, prob_ventaValorMercado, prob_ventaValorInmobiliario))
      addvar!(m, lb_param, ub_param)
      add_ineq_constraint!(m, x -> g(x))
  
      alg = BayesOptAlg(IpoptAlg())
      options = BayesOptOptions(
          sub_options = IpoptOptions(print_level = 0), maxiter = 10, ctol = 1e-4,
          ninit = 2, initialize = true, postoptimize = false, fit_prior = true,
      )
      r = optimize(m, alg, lb_param, options = options);
      fopt = r.minimum
      mu_opt = r.minimizer[1]
      sigma_opt = r.minimizer[2]
  
      return fopt, mu_opt, sigma_opt
end
  
function ajustaPrecioReserva(valorMercado_lotes::Vector{Float64}, valorInmobiliario_combis::Vector{Float64}, C::Matrix{Int64}, prob_ventaValorMercado, prob_ventaValorInmobiliario)
      #Esta versión acepta los vectores valorMercado_lotes y valorInmobiliario_combis además de la matriz de combinaciones C
      
      numLotes = length(valorMercado_lotes)
      fopt = zeros(numLotes,1)
      mu_vec = zeros(numLotes,1)
      sigma_vec = zeros(numLotes,1)
      for k = 1:numLotes
          flag = C[:,k]
          valorInmobiliario_vec = valorInmobiliario_combis[ flag .== 1] ./ sum(C[flag .== 1,:], dims=2)
          valorInmobiliario = sum(valorInmobiliario_vec) / length(valorInmobiliario_vec)
          fopt[k], mu_vec[k], sigma_vec[k] = ajustaPrecioReserva(valorMercado_lotes[k], valorInmobiliario, prob_ventaValorMercado, prob_ventaValorInmobiliario)
      end
      return fopt, mu_vec, sigma_vec
end

function f(x::AbstractVector, mu_pre, sigma_pre, mu_post, sigma_post, valorInmobiliario_combis, C, p)
      numCombis, numLotes = size(C)
      prob_vec_pre = [Distributions.cdf(Distributions.LogNormal(mu_pre[i], sigma_pre[i]), x[i]) for i = 1:numLotes]
      prob_vec_post = [Distributions.cdf(Distributions.LogNormal(mu_post[i], sigma_post[i]), x[i]) for i = 1:numLotes]

      utilEsp = sum(
                        (valorInmobiliario_combis[k] - sum(C[k,i] * x[i] for i in 1:numLotes)) * 
                        prod(C[k,i] == 1 ? 
                              (i == p ? prob_vec_pre[i] : prob_vec_post[i]) : 
                              1 - (i == p ? prob_vec_pre[i] : prob_vec_post[i]) for i in 1:numLotes) for k in 1:numCombis)

      return -utilEsp
end


function g(x::AbstractVector, mu_pre, sigma_pre, mu_post, sigma_post, C, minProb)
      numCombis, numLotes = size(C)
      prob_vec_pre = [Distributions.cdf(Distributions.LogNormal(mu_pre[i], sigma_pre[i]), x[i]) for i = 1:numLotes]
      prob_vec_post = [Distributions.cdf(Distributions.LogNormal(mu_post[i], sigma_post[i]), x[i]) for i = 1:numLotes]

      probCombis = sum( [ prod([C[k, i] == 1 ? (i == p ? prob_vec_pre[i] : prob_vec_post[i]) : 1 - (i == p ? prob_vec_pre[i] : prob_vec_post[i]) for i = 1:numLotes]) 
                      for k = 1:numCombis ] )

      return minProb - probCombis
end


Ad = [0 1 0 0 0;
      1 0 1 0 0;
      0 1 0 1 0;
      0 0 1 0 1;
      0 0 0 1 0]


p = 3
minProb = 0.00


numLotes = size(Ad,2)
valorMercado_lotes = vec(ones(numLotes,1) .* 90)

C = graphMod.node_combis(Ad, flag_mat = true) #matriz de Combinaciones de lotes

prob_ventaValorMercado = .15
prob_ventaValorInmobiliario = .60

valorPropietario_combis = sum(C, dims=2) .* (1.02.^(sum(C, dims=2))*200) #valor de los combis para el Inmobiliario
valorPropietario_combis[ sum(C, dims=2) .== 1 ] .= (90 + 200) / 2
valorPropietario_combis = vec(valorPropietario_combis)
fopt, mu_pre, sigma_pre = ajustaPrecioReserva(valorMercado_lotes, valorPropietario_combis, C, prob_ventaValorMercado, prob_ventaValorInmobiliario)

Ad_p = copy(Ad)
Ad_p[p,:] .= 0
Ad_p[:,p] .= 0
graphMod.graphPlot(Ad_p)
C_p = graphMod.node_combis(Ad_p, flag_mat = true) #matriz de Combinaciones de lotes
valorPropietario_combis_p = sum(C_p, dims=2) .* (1.02.^(sum(C_p, dims=2))*200) #valor de los combis para los Propietarios
valorPropietario_combis_p[ sum(C_p, dims=2) .== 1 ] .= (90 + 200) / 2 #los terrenos solos son menos atractivos post compra del pivote
valorPropietario_combis_p = vec(valorPropietario_combis_p)
fopt, mu_post, sigma_post = ajustaPrecioReserva(valorMercado_lotes, valorPropietario_combis_p, C_p, prob_ventaValorMercado, prob_ventaValorInmobiliario)
# mu_post = mu_pre; sigma_post = sigma_pre

valorInmobiliario_combis = sum(C, dims=2) .* (1.02.^(sum(C, dims=2))*200) #valor de los combis para el Inmobiliario
valorInmobiliario_combis[ sum(C, dims=2) .== 1 ] .= 90
valorInmobiliario_combis = vec(valorInmobiliario_combis)

lb_lotes = valorMercado_lotes
ub_lotes = 3 .* valorMercado_lotes

m = NonconvexBayesian.Model()
set_objective!(m, x -> f(x, mu_pre, sigma_pre, mu_post, sigma_post, valorInmobiliario_combis, C, p))
addvar!(m, lb_lotes, ub_lotes)
add_ineq_constraint!(m, x -> g(x, mu_pre, sigma_pre, mu_post, sigma_post, C, minProb))

alg = BayesOptAlg(IpoptAlg())
options = BayesOptOptions(
sub_options = IpoptOptions(print_level = 0), maxiter = 10, ctol = 1e-4,
ninit = 2, initialize = true, postoptimize = false, fit_prior = true,
)
r = optimize(m, alg, lb_lotes, options = options);

fopt = -r.minimum
xopt = r.minimizer