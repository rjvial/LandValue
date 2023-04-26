using LandValue
# Este caso asume multiples etapas de ofertas

T = 4 # numero de ofertas que se puede hacer

valorInmobiliario_lote = 200.

valor_lb = 90.
valor_ub = valorInmobiliario_lote

prob_lb = .10
prob_ub = .90

α = log( log(1-prob_lb) / log(1-prob_ub) ) / log( valor_lb / valor_ub )
λ = valor_ub / exp( log(log(1/(1-prob_ub))) / α )


fopt, xopt = bid_price_dinamico_weibull(valorInmobiliario_lote, α, λ, T)