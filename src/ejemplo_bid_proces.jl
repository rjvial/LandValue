using LandValue

# Ad = [0 1;
#       1 0]

# Ad =    [0 1 0;
#          1 0 1;
#          0 1 0]

# Ad = [0 1 1;
#       1 0 1;
#       1 1 0]

Ad = [0 1 0 0 0;
      1 0 1 0 0;
      0 1 0 1 0;
      0 0 1 0 1;
      0 0 0 1 0]

# Ad =    [0 1 1 0 0 0;
#          1 0 1 1 0 1;
#          1 1 0 1 1 0;
#          0 1 1 0 1 1;
#          0 0 1 1 0 1;
#          0 1 0 1 1 0]


minProb = 0.0

graphMod.graphPlot(Ad)
         
numLotes = size(Ad,2)
valorMercado_lotes = vec(ones(numLotes,1) .* 90)

C = graphMod.node_combis(Ad, flag_mat = true) #matriz de Combinaciones de lotes

prob_compraValorMercado = .15
prob_compraValorInmobiliario = .60

valorPropietario_combis = sum(C, dims=2) .* (1.02.^(sum(C, dims=2))*200) #valor de los combis para los Propietarios
valorPropietario_combis[ sum(C, dims=2) .== 1 ] .= (90 + 200) / 2
valorPropietario_combis = vec(valorPropietario_combis)
fopt, mu_vec, sigma_vec = ajustaPrecioReserva(valorMercado_lotes, valorPropietario_combis, C, prob_compraValorMercado, prob_compraValorInmobiliario)

valorInmobiliario_combis = sum(C, dims=2) .* (1.02.^(sum(C, dims=2))*200) #valor de los combis para el Inmobiliario
valorInmobiliario_combis[ sum(C, dims=2) .== 1 ] .= 90
valorInmobiliario_combis = vec(valorInmobiliario_combis)

fopt, xopt, prob_lotes, prob_combis = bid_prices(valorMercado_lotes, valorInmobiliario_combis, C, mu_vec, sigma_vec, minProb)