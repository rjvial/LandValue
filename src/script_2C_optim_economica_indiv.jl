using LandValue, Distributed, DotEnv


# Para cómputos sobre la base de datos usar codigo_predial = []
codigo_predial = [151600231900001, 151600231900002, 151600231900003, 151600231900004, 151600231900005]

tipoOptimizacion = "provisoria" #"economica"

DotEnv.load("secrets.env") #Caso Docker
datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
datos_mygis_db = ["gis_data", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
# datos_LandValue = ["landengines_local", "postgres", "", "localhost"]
# datos_mygis_db = ["gis_data_local", "postgres", "", "localhost"]

conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
conn_mygis_db = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])

id_ = 0

# datos = [] #Si se quiere que la información se obtenga de la base se datos
dcc, resultados, xopt, vecColumnNames, vecColumnValue, id_ = funcionPrincipal(tipoOptimizacion, codigo_predial, id_, datos_LandValue, datos_mygis_db, [])

displayResults(resultados, dcc)

