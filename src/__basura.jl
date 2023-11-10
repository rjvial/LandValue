using LandValue

C = [1 1 1 0 0 0
     0 1 1 0 0 0
     0 0 0 1 1 1
     0 0 0 1 1 0
     1 1 1 1 1 0
     0 1 1 1 1 1
     1 1 1 1 1 1]

valorMercado_lotes = 100 * ones(6,1)
superficie_lotes = 100 * ones(6,1)
valorInmobiliario_combis = [150 * 3
                            145 * 2
                            150 * 3
                            145 * 2
                            160 * 5
                            160 * 5
                            163 * 6]


# C = [1 1 0 0
#      0 1 1 0
#      1 1 1 0
#      1 1 0 1
#      0 1 1 1
#      1 1 1 1]

# valorMercado_lotes = 100 * ones(4,1)
# superficie_lotes = 100 * ones(4,1)
# valorInmobiliario_combis = [145 * 2
#                             145 * 2
#                             150 * 3
#                             150 * 3
#                             150 * 3
#                             155 * 4]

delta_porcentual = 0.1


x_opt = optimal_lot_selection(C)



popt_r, util_opt_r, unit_price_r, prob_combis_r = optimal_pricing(C, valorMercado_lotes, superficie_lotes, valorInmobiliario_combis, delta_porcentual)

rent_combi = (valorInmobiliario_combis .- C * popt_r) ./ (C * popt_r)
maxPerdida_combi = (C * valorMercado_lotes .- C * popt_r) ./ (C * popt_r)

[rent_combi maxPerdida_combi]