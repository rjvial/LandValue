using LandValue
# Este caso asume que aprendizaje con precio de reserva distribuido uniforme

T = 20 # numero de ofertas que se puede hacer

valorMercado_lote = 90
valorInmobiliario_lote = 200

fopt, xopt = bid_price_aprendizaje_uniforme(valorMercado_lote, valorInmobiliario_lote, T)