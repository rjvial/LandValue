using LandValue, Distributed, DotEnv

codigo_predial = [151600140700001, 151600140700002, 151600140700003, 151600140700006, 151600140700007, 151600140700008, 151600140700009, 151600140700010]
# Para cómputos sobre la base de datos usar codigo_predial = []
tipoOptimizacion = "provisoria" #"economica"

DotEnv.load("secrets.env") #Caso Docker
datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
datos_mygis_db = ["gis_data", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
# datos_LandValue = ["landengines_local", "postgres", "", "localhost"]
# datos_mygis_db = ["gis_data_local", "postgres", "", "localhost"]

conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
conn_mygis_db = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])


id_ = 0

dcc, resultados, xopt, vecColumnNames, vecColumnValue, id_ = funcionPrincipal(tipoOptimizacion, codigo_predial, id_, datos_LandValue, datos_mygis_db, datos)

displayResults(resultados, dcc)

# Para reinicializar tabla_resultados_cabidas
# update tabla_resultados_cabidas
# set norma_min_estacionamientos_vendibles = 0,
#     norma_min_estacionamientos_visita = 0,
#     norma_min_estacionamientos_discapacitados = 0,
#     cabida_tipo_deptos = 0,
#     cabida_num_deptos = 0,
#     cabida_ocupacion = 0,
#     cabida_constructibilidad = 0,
#     cabida_superficie_interior = 0,
#     cabida_superficie_terraza = 0,
#     cabida_superficie_comun = 0,
#     cabida_superficie_edificada_snt = 0,
#     cabida_superficie_por_piso = 0,
#     cabida_estacionamientos_vendibles = 0,
#     cabida_estacionamientos_visita = 0,
#     cabida_num_estacionamientos = 0,
#     cabida_num_bicicleteros = 0,
#     cabida_num_bodegas = 0,
#     terreno_costo = 0,
#     terreno_costo_unit = 0,
#     terreno_costo_corredor = 0,
#     terreno_costo_demolicion = 0,
#     terreno_otros = 0,
#     terreno_costo_total = 0,
#     terreno_costo_unit_total = 0,
#     holgura_ocupacion = 0,
#     holgura_constructibilidad = 0,
#     holgura_densidad = 0,
#     indicador_ingresos_ventas = 0,
#     indicador_costo_total = 0,
#     indicador_margen_antes_impuesto = 0,
#     indicador_impuesto_renta = 0,
#     indicador_utilidad_despues_impuesto = 0,
#     indicador_rentabilidad_total_bruta = 0,
#     indicador_rentabilidad_total_neta = 0,
#     indicador_incidencia_terreno = 0

# update tabla_combinacion_predios
# set status = 1
# where status = 2