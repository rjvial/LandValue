using LandValue
# Este caso asume multiples etapas de ofertas

T = 20 # numero de ofertas que se puede hacer

valorMercado_lote = 90.
valorInmobiliario_lote = 200.

prob_ventaValorMercado = .15
prob_ventaValorInmobiliario = .60

_, mu, sigma = ajustaPrecioReserva(valorMercado_lote, valorInmobiliario_lote, prob_ventaValorMercado, prob_ventaValorInmobiliario)

fopt, xopt = bid_price_dinamico(valorMercado_lote, valorInmobiliario_lote, mu, sigma, T)