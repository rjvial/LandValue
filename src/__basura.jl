using LandValue

C = [1 1 1 0 0 0
     0 1 1 0 0 0
     0 0 0 1 1 1
     0 0 0 1 1 0
     1 1 1 1 1 0
     0 1 1 1 1 1
     1 1 1 1 1 1]

valorMercado_lotes = 100 * ones(6,1)
num_lotes = length(valorMercado_lotes)
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

delta_lotes = .1
delta_combis = .2
delta_opt_lotes = .1
delta_opt_combis = .2

# x_opt = optimal_lot_selection(C)

popt_r, util_opt_r = optimal_pricing(C, valorMercado_lotes, superficie_lotes, valorInmobiliario_combis, delta_lotes, delta_combis, delta_opt_lotes, delta_opt_combis)

p_lotes = popt_r[1][1:num_lotes]
p_combis = popt_r[1][num_lotes+1:end]

display(p_lotes)
display([valorInmobiliario_combis * (1-delta_opt_combis) p_combis valorInmobiliario_combis * (1+delta_opt_combis)])

display(util_opt_r)