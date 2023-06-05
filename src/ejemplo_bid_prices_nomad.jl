using LandValue, NOMAD


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
        valorInmobiliario_vec = valorInmobiliario_combis[ C[:,k] .== 1] ./ sum(C[C[:,k] .== 1,:], dims=2)
        valorInmobiliario = sum(valorInmobiliario_vec) / length(valorInmobiliario_vec)
        α_vec[k], λ_vec[k] = ajustaPrecioReserva(valorMercado_lotes[k], valorInmobiliario, prob_ventaValorMercado, prob_ventaValorInmobiliario)
    end
    return α_vec, λ_vec
end

function prob_compra(x::AbstractVector, α_vec, λ_vec, valorMercado_lotes, C, minProb) #Restricción para asegurar una probabilidad mínima de éxito
    numCombis, numLotes = size(C)
    δ_vec = valorMercado_lotes .* 0.9

    prob_vec = [x[i] - δ_vec[i] < 0 ? 0 : 1 - exp(-((x[i] - δ_vec[i]) / λ_vec[i])^α_vec[i]) for i = 1:numLotes]

    # calculate the sum of the product of probabilities for each combination
    probCombis = sum(
        # calculate the product of probabilities for a single combination
        prod(C[k,i] == 1 ? prob_vec[i] : 1 - prob_vec[i] for i=1:numLotes)
        
        # loop over all combinations
        for k = 1:numCombis
    )

    return probCombis
end

function util_esp(x, α_vec, λ_vec, valorMercado_lotes, valorInmobiliario_combis, C) 
    numCombis, numLotes = size(C)
    δ_vec = valorMercado_lotes .* 0.9

    prob_vec = [x[i] - δ_vec[i] < 0 ? 0 : 1 - exp(-((x[i] - δ_vec[i]) / λ_vec[i])^α_vec[i]) for i = 1:numLotes]

    utilEsp = sum(
        # expected utility for a single combination
        (valorInmobiliario_combis[k] - sum([C[k,i] * x[i] for i=1:numLotes])) * 
        prod([C[k,i] == 1 ? prob_vec[i] : 1 - prob_vec[i] for i=1:numLotes])
        
        # loop over all combinations
        for k = 1:numCombis
    )

    return utilEsp
end

function f(x, α_vec, λ_vec, valorMercado_lotes, valorInmobiliario_combis, C, minProb) 
    
    utilEsp = util_esp(x, α_vec, λ_vec, valorMercado_lotes, valorInmobiliario_combis, C)

    constraints = []
    constraints = push!(constraints, 10000*(minProb - prob_compra(x, α_vec, λ_vec, valorMercado_lotes, C, minProb)))

    # Integración Función Objetivo con Restricciones
    bb_outputs = [-utilEsp; constraints]
    success = true
    count_eval = true

    return (success, count_eval, bb_outputs)
end


Ad = [0 1 0 1 1;
      1 0 1 1 0;
      0 1 0 0 0;
      1 1 0 0 1;
      1 0 0 1 0]

# Ad = [0 1 0;
#       1 0 1;
#       0 1 0]
graphMod.graphPlot(Ad)

numLotes = size(Ad,2)

minProb = 0.0
valorMercado_lote = 38888.; prob_compraValorMercado = .1
valorInmobiliario_lote = 45000.; prob_compraValorInmobiliario = .5

valorMercado_lotes = vec(ones(numLotes,1) .* valorMercado_lote)

C = graphMod.node_combis(Ad, flag_mat = true) #matriz de Combinaciones de lotes

valorInmobiliario_combis = sum(C, dims=2) .* valorInmobiliario_lote #valor de los combis para el Inmobiliario
valorInmobiliario_combis[ sum(C, dims=2) .== 1 ] .= valorMercado_lote
valorInmobiliario_combis = vec(valorInmobiliario_combis)
α_vec, λ_vec = ajustaPrecioReserva(valorMercado_lotes, valorInmobiliario_combis, C, prob_compraValorMercado, prob_compraValorInmobiliario)


lb_lotes = valorMercado_lotes
ub_lotes = 3 .* valorMercado_lotes

obj_nomad = x -> f(x, α_vec, λ_vec, valorMercado_lotes, valorInmobiliario_combis, C, minProb)

num_inputs = length(lb_lotes); # Number of inputs of the blackbox. Is required to be > 0
num_outputs = 1 + 1; # Number of outputs of the blackbox. Is required to be > 0
output_types = vcat(["OBJ"], ["PB" for i in 1:1]); # "OBJ" objective value to be minimized, "PB" progressive barrier constraint, "EB" extreme barrier constraint
input_types = vcat(["R" for i in 1:num_inputs]); # A vector containing String objects that define the types of inputs to be given to eval_bb (the order is important). "R" Real/Continuous, "B" Binary,"I" Integer

p = NOMAD.NomadProblem(num_inputs, num_outputs, output_types, obj_nomad; 
                input_types = input_types, 
                lower_bound = lb_lotes, 
                upper_bound = ub_lotes)


p.options.display_degree = 0 
#p.options.max_bb_eval = MaxSteps; # Fix some options

# solve problem starting from the point
initSol = lb_lotes

result = NOMAD.solve(p, initSol);

xopt = result.x_best_feas
fopt = util_esp(xopt, α_vec, λ_vec, valorMercado_lotes, valorInmobiliario_combis, C)
prob_opt = prob_compra(xopt, α_vec, λ_vec, valorMercado_lotes, C, minProb)

display(xopt)
display(" ")
display("fopt: " * string(fopt))
display("Prob Compra: " * string(prob_opt))