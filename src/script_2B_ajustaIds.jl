using LandValue, Distributed, DotEnv 

DotEnv.load("secrets.env") #Caso Docker
datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
datos_mygis_db = ["gis_data", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]


conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
conn_mygis_db = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])

query_combinaciones_str = """
select combi_predios_str, id from tabla_combinacion_predios
"""
df_combinaciones = pg_julia.query(conn_LandValue, query_combinaciones_str)
numRows, numCols = size(df_combinaciones)

for r = 1:numRows
    combi_predios_r = eval(Meta.parse(df_combinaciones[r, "combi_predios_str"]))
    codPredialStr = replace(replace(string(combi_predios_r), "[" => "("), "]" => ")")
    display(string(r) * "  " * codPredialStr)

    executeStr = "UPDATE tabla_resultados_cabidas SET id = " * string(df_combinaciones[r, "id"]) * " WHERE combi_predios = \'" * df_combinaciones[r, "combi_predios_str"] * "\'"
    pg_julia.query(conn_LandValue, executeStr)
end

