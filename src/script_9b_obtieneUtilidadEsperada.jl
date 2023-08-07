using LandValue, DotEnv

DotEnv.load("secrets.env") #Caso Docker
datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
datos_mygis_db = ["gis_data", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
# datos_LandValue = ["landengines_local", "postgres", "", "localhost"]
# datos_mygis_db = ["gis_data_local", "postgres", "", "localhost"]

conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
conn_mygis_db = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])


query_combi_locations = """
select * from combi_locations
order by id_combi_list ASC
"""
df_combi_locations = pg_julia.query(conn_LandValue, query_combi_locations)
numRows_combi, numCols_combi = size(df_combi_locations)

# display("Agrega columna a combi_locations")
# query_add_column = """
# ALTER TABLE combi_locations
#     ADD COLUMN IF NOT EXISTS util_esp_combi double precision
# """
# pg_julia.query(conn_LandValue, query_add_column)


for r = 1:numRows_combi

    unique_lotes_r = df_combi_locations[r, "unique_lotes"]
    unique_lotes_r = replace(replace(replace(string(unique_lotes_r), "[" => "("), "]" => ")"), "; " => ", ")

    query_valor_combi_r = """
    select id, valor_combi from tabla_resultados_cabidas
    where id_combi_list = $r and gap >= 0
    order by id ASC
    """
    df_valor_combi_r = pg_julia.query(conn_LandValue, query_valor_combi_r)


    query_sup_prop_r = """
    select sup_terreno_edif from datos_predios_vitacura
    where codigo_predial in $unique_lotes_r
    order by codigo_predial ASC
    """
    df_sup_prop_r = pg_julia.query(conn_mygis_db, query_sup_prop_r)

    query_valor_prop_r = """
    select precio_estimado_final from tabla_propiedades
    where rol in $unique_lotes_r
    order by rol ASC
    """
    df_valor_prop_r = pg_julia.query(conn_LandValue, query_valor_prop_r)

    # df_combi_locations_r = df_combi_locations[r, "id_combi_vec"]


end