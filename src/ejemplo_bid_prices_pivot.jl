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

fopt, xopt = bid_prices_pivot(valorMercado_lotes, valorInmobiliario_combis, C, mu_pre, sigma_pre, mu_post, sigma_post, p, minProb)
