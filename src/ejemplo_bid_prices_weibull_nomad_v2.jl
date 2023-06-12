using LandValue, NOMAD


function ajustaPrecioReserva(valorMercado_lote::Float64, valorInmobiliario_lote::Float64, prob_ventaValorMercado::Float64, prob_ventaValorInmobiliario::Float64)
    #Esta función ajusta los parámetros α y λ de una distribución Weibull del precio de reserva r de manera que:
    # prob(r < valorMercado) = prob_ventaValorMercado y prob(r < valorInmobiliario) = prob_ventaValorInmobiliario

    prob_lb = prob_ventaValorMercado
    prob_ub = prob_ventaValorInmobiliario
    p_lb = valorMercado_lote
    δ = p_lb * 0.9
    p_ub = valorInmobiliario_lote
    α = log( log(1 - prob_lb) / log(1 - prob_ub) ) / log( (p_lb - δ) / (p_ub - δ) )
    λ = (p_ub - δ) / exp( log(log(1/(1 - prob_ub))) / α )
    return α, λ
end
function ajustaPrecioReserva(valorMercado_lotes::Vector{Float64}, superficie_lotes::Vector{Float64}, valorInmobiliario_combis::Vector{Float64}, C::Matrix{Int64}, prob_ventaValorMercado, prob_ventaValorInmobiliario)
    #Esta versión acepta los vectores valorMercado_lotes y valorInmobiliario_combis además de la matriz de combinaciones C
    
    numLotes = length(valorMercado_lotes)
    α_vec = zeros(numLotes,1)
    λ_vec = zeros(numLotes,1)
    superficie_combis = [sum(C[i,:] .* superficie_lotes) for i in eachindex(valorInmobiliario_combis)]
    valorInmobiliarioUnit_combis = valorInmobiliario_combis ./ superficie_combis
    for k = 1:numLotes
        valorMercado_lote = valorMercado_lotes[k]
        valorInmobiliarioUnitPromedio_k =  sum(valorInmobiliarioUnit_combis[C[:,k] .== 1]) / sum(C[:,k] .== 1)
        valorInmobiliario_lote = valorInmobiliarioUnitPromedio_k * superficie_lotes[k]
        α_vec[k], λ_vec[k] = ajustaPrecioReserva(valorMercado_lote, valorInmobiliario_lote, prob_ventaValorMercado, prob_ventaValorInmobiliario)
    end
    return α_vec, λ_vec
end

function prob_lote(x, α, λ, valorMercado_lote)
    δ = valorMercado_lote .* 0.9
    return x - δ < 0 ? 0 : 1 - exp(-((x - δ) / λ)^α)
end
function prob_lotes(x, α_vec, λ_vec, valorMercado_lotes, C)
    numCombis, numLotes = size(C)
    return [prob_lote(x[i], α_vec[i], λ_vec[i], valorMercado_lotes[i]) for i = 1:numLotes]
end

function prob_combis(x, α_vec, λ_vec, valorMercado_lotes, C)
    numCombis, numLotes = size(C)

    probLotes = prob_lotes(x, α_vec, λ_vec, valorMercado_lotes, C)
    probCombis = [prod([C[k,i] == 1 ? probLotes[i] : 1 - probLotes[i] for i = 1:numLotes]) for k = 1:numCombis]
    return probCombis
end

function prob_compra(x::AbstractVector, α_vec, λ_vec, valorMercado_lotes, C) #Restricción para asegurar una probabilidad mínima de éxito

    probCombis = prob_combis(x, α_vec, λ_vec, valorMercado_lotes, C)
    probCompra = sum( probCombis )
    return probCompra
end

function util_esp(x, α_vec, λ_vec, valorMercado_lotes, valorInmobiliario_combis, C) 
    numCombis, numLotes = size(C)

    probCombis = prob_combis(x, α_vec, λ_vec, valorMercado_lotes, C)
    utilEsp = sum([ (valorInmobiliario_combis[k] - sum(C[k,:] .* x)) * probCombis[k] for k = 1:numCombis ])
    return utilEsp
end

function inv_esp(x, α_vec, λ_vec, valorMercado_lotes, C) 
    numCombis, numLotes = size(C)

    probCombis = prob_combis(x, α_vec, λ_vec, valorMercado_lotes, C)
    invEsp = sum( [sum(C[k,:] .* x) * probCombis[k] for k = 1:numCombis ])
    return invEsp
end

function f(x, α_vec, λ_vec, valorMercado_lotes, valorInmobiliario_combis, C, minUtil) 
    
    probCompra = prob_compra(x, α_vec, λ_vec, valorMercado_lotes, C)
    utilEsp = util_esp(x, α_vec, λ_vec, valorMercado_lotes, valorInmobiliario_combis, C)
    
    constraints = []
    constraints = push!(constraints, 100000*(minUtil - utilEsp/probCompra))

    # Integración Función Objetivo con Restricciones
    bb_outputs = [-probCompra; constraints]
    success = true
    count_eval = true

    return (success, count_eval, bb_outputs)
end


# Ingresar mínima probabilidad de venta 
minUtil = 8000

# Ingresar matriz C de combinaciones
Ad = [0 1 0 1 1;
      1 0 1 1 0;
      0 1 0 0 0;
      1 1 0 0 1;
      1 0 0 1 0]
graphMod.graphPlot(Ad)
C = graphMod.node_combis(Ad, flag_mat = true) #matriz de Combinaciones de lotes

# Ingresar vector valorMercado_lotes 
numLotes = size(C, 2)
valorMercado_lote = 38888.; prob_compraValorMercado = .1
valorMercado_lotes = vec(ones(numLotes,1) .* valorMercado_lote)

# Ingresar vector valorInmobiliario_combis
valorInmobiliario_lote = 45000.; prob_compraValorInmobiliario = .9
valorInmobiliario_combis = sum(C, dims=2) .* valorInmobiliario_lote #valor de los combis para el Inmobiliario
valorInmobiliario_combis[ sum(C, dims=2) .== 1 ] .= valorMercado_lote
valorInmobiliario_combis = vec(valorInmobiliario_combis)

# Ingresar superficie_lotes
superficie_lotes = [700. for i = 1:5]



α_vec, λ_vec = ajustaPrecioReserva(valorMercado_lotes, superficie_lotes, valorInmobiliario_combis, C, prob_compraValorMercado, prob_compraValorInmobiliario)

lb_lotes = valorMercado_lotes
ub_lotes = 3 .* valorMercado_lotes

obj_nomad = x -> f(x, α_vec, λ_vec, valorMercado_lotes, valorInmobiliario_combis, C, minUtil)

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
#xopt = [36000, 36000, 36000, 36000, 36000]
util_opt = util_esp(xopt, α_vec, λ_vec, valorMercado_lotes, valorInmobiliario_combis, C)
prob_opt = prob_compra(xopt, α_vec, λ_vec, valorMercado_lotes, C)
inv_opt = inv_esp(xopt, α_vec, λ_vec, valorMercado_lotes, C)

display(xopt)
display(" ")
display("Util. Esperada: " * string(util_opt))
display("Inv. Esperada: " * string(inv_opt))
display("Prob. Compra: " * string(prob_opt))
display("Util. Compra: " * string(util_opt/prob_opt))
display("Inv. Compra: " * string(inv_opt/prob_opt))
display("Retorno Inversion: " * string(util_opt/inv_opt))