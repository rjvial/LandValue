using LandValue, NOMAD

##########################
# Parámetros necesarios
##########################

# 1) Probabilidad de Compra de Lote a Precio de Mercado
prob_compraValorMercado = .1

# 2) Probabilidad de compra de Lote a valor inmobiliario
prob_compraValorInmobiliario = .9

# 3) Matriz de combinaciones posibles
# Ad = [0 1 1 0 0 0 0;
#       1 0 1 0 0 0 0;
#       1 1 0 0 0 0 0;
#       0 0 0 0 1 1 0;
#       0 0 0 1 0 0 1;
#       0 0 0 1 0 0 1;
#       0 0 0 0 1 1 0]
# graphMod.graphPlot(Ad)
# C = graphMod.node_combis(Ad, flag_mat = true) #Genera matriz de Combinaciones de lotes
# C = [1 1 0 0; 0 1 1 0; 0 1 0 1; 1 1 1 0; 1 1 0 1; 0 1 1 1]
# C = [0 0 0 0]
C = [1 1 0 0; 0 1 1 0; 1 0 0 1; 1 1 0 1; 1 1 1 0; 1 1 1 1]
# C = [1 1 1 0; 0 1 1 1; 1 1 1 1]
numLotes = size(C, 2)

# 4) Valor de mercado de los lotes
valorMercado_lote = 38888.  # * .9 = 35000 = precio_lb
valorMercado_lotes = vec(ones(numLotes,1) .* valorMercado_lote)
 
# 5) Tamaño de los lotes
superficie_lotes = [700. for i = 1:numLotes]

# 6) Valor inmobiliario de las combinaciones
valorInmobiliario_lote = 50000.
valorInmobiliario_combis = sum(C, dims=2) .* valorInmobiliario_lote #valor de los combis para el Inmobiliario
valorInmobiliario_combis[ sum(C, dims=2) .<= 1 ] .= valorMercado_lote
valorInmobiliario_combis = vec(valorInmobiliario_combis)

# 7) Mínima probabilidad de compra exigida
minProb = 0.0


display("Maximizando utilidad esperada considerando que todos los lotes están disponibles")
xopt, util_opt, inv_opt = optimal_pricing(C, valorMercado_lotes, superficie_lotes, valorInmobiliario_combis, prob_compraValorMercado, prob_compraValorInmobiliario, minProb)

mat_val = zeros(numLotes, numLotes)
vec_util = zeros(numLotes, 1)
for i = 1:numLotes
    display("Maximizando utilidad esperada excluyendo el lote N° " * string(i))
    flag_i = C[:, i] .== 0
    C_i = C[flag_i, :]
    valorInmobiliario_combis_i = valorInmobiliario_combis[flag_i]
    if isempty(C_i)
        C_i = C .* 0
        valorInmobiliario_combis_i = copy(valorInmobiliario_combis)
    end
    xopt_i, util_opt_i, inv_opt_i = optimal_pricing(C_i, valorMercado_lotes, superficie_lotes, valorInmobiliario_combis_i, prob_compraValorMercado, prob_compraValorInmobiliario, minProb)
    mat_val[i,:] = xopt_i
    mat_val[i,i] = 0
    vec_util[i] = util_opt_i
end

display((util_opt .- vec_util))




# xx = 35000:50000
# k = 3
# y1 = [prob_lote(xx[i], α_vec[k], λ_vec[k], valorMercado_lote, prob_compraValorMercado) for i = 2:length(xx)]
# y0 = [prob_lote(xx[i], α_vec[k], λ_vec[k], valorMercado_lote, prob_compraValorMercado) for i = 1:length(xx)-1]
# plot(xx[2:end], y1 .- y0) 


