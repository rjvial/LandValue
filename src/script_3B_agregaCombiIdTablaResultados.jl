using LandValue, DotEnv

# Establece las conexiones a las Base de Datos
# conn_LandValue = pg_julia.connection("landengines", ENV["USER"], ENV["PW"], ENV["HOST"])

DotEnv.load("secrets.env") #Caso Docker
datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]

conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])


# Agrega columna id_combi_list a tabla_resultados_cabidas
query_resultados_str = """
ALTER TABLE tabla_resultados_cabidas
  ADD COLUMN IF NOT EXISTS id_combi_list integer;
"""
df_resultados = pg_julia.query(conn_LandValue, query_resultados_str)

query_resultados_str = """
select combi_predios, terreno_costo from tabla_resultados_cabidas
"""
df_resultados = pg_julia.query(conn_LandValue, query_resultados_str)
numRows_resultados, numCols_resultados = size(df_resultados)


query_combi_str = """
select combi_list, id_combi_list from combi_locations
"""
df_combi = pg_julia.query(conn_LandValue, query_combi_str)
numRows_combi, numCols_combi = size(df_combi)

# Completa columna id_combi_list
for r = 1:numRows_combi
    id_combi_str = string(df_combi[r, "id_combi_list"])

    combi_list_r = df_combi[r, "combi_list"]
    vec_combi_list = eval(Meta.parse(replace(replace(replace(replace(string(combi_list_r), "{" => "["), "}" => "]")))))


    for k in eachindex(vec_combi_list)
        predios_ik_str = string(vec_combi_list[k])
        query_predios_str = """
                UPDATE tabla_resultados_cabidas SET id_combi_list = id_combi_str_
                WHERE combi_predios = \'predios_ik_str_\'
                """
        query_predios_str = replace(query_predios_str, "id_combi_str_" => id_combi_str)
        query_predios_str = replace(query_predios_str, "predios_ik_str_" => predios_ik_str)
        df_predios = pg_julia.query(conn_LandValue, query_predios_str)

    end

    display(string(r) * "  " * combi_list_r)

end

# Agrega columna valor_combi a tabla_resultados_cabidas
query_resultados_str = """
ALTER TABLE tabla_resultados_cabidas
  ADD COLUMN IF NOT EXISTS valor_combi double precision;
"""
pg_julia.query(conn_LandValue, query_resultados_str)


# Agrega columna gap a tabla_resultados_cabidas
query_resultados_str = """
ALTER TABLE tabla_resultados_cabidas
  ADD COLUMN IF NOT EXISTS gap double precision,
  ADD COLUMN IF NOT EXISTS gap_porcentual double precision;
"""
pg_julia.query(conn_LandValue, query_resultados_str)


infileStr = "C:\\Users\\rjvia\\OneDrive\\_traspasos\\qgis_env\\aux_files\\Valorizacion_Sitios.csv"
df_propiedades = pg_julia.csv2df(infileStr)
numRows_propiedades, numCols_propiedades = size(df_propiedades)

for r = 1:numRows_resultados
    list_prop_r = df_resultados[r, "combi_predios"]
    vec_list_prop = eval(Meta.parse(list_prop_r))
    valorizacion_r = 0
    for p in eachindex(vec_list_prop)
        valorizacion_rp = df_propiedades[(df_propiedades.Rol.==vec_list_prop[p]), "Valorizacion"][1]
        if valorizacion_rp == "NA"
            break
        else
            valorizacion_rp = parse(Float64, valorizacion_rp)
        end

        valorizacion_r += valorizacion_rp
    end
    query_propiedades_str = """
      UPDATE tabla_resultados_cabidas SET valor_combi = valor_combi_str_
      WHERE combi_predios = \'list_prop_r_\'
      """
    query_propiedades_str = replace(query_propiedades_str, "valor_combi_str_" => string(valorizacion_r))
    query_propiedades_str = replace(query_propiedades_str, "list_prop_r_" => list_prop_r)
    pg_julia.query(conn_LandValue, query_propiedades_str)

    terreno_costo_r = df_resultados[r, "terreno_costo"]
    gap_r = terreno_costo_r - valorizacion_r
    gap_porcentual_r = (terreno_costo_r - valorizacion_r) / valorizacion_r
    if string(gap_porcentual_r) != "Inf" && lowercase(string(gap_porcentual_r)) != "nan"
        query_gap_str = """
          UPDATE tabla_resultados_cabidas 
          SET gap = gap_str_, gap_porcentual = gap_porcentual_r_
          WHERE combi_predios = \'list_prop_r_\'
          """
        query_gap_str = replace(query_gap_str, "gap_str_" => string(gap_r))
        query_gap_str = replace(query_gap_str, "gap_porcentual_r_" => string(gap_porcentual_r))
        query_gap_str = replace(query_gap_str, "list_prop_r_" => list_prop_r)
        pg_julia.query(conn_LandValue, query_gap_str)
    end
    display(string(r))

end







# pg_dump -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres -d landengines_dev -t "combi_locations" -t "tabla_combinacion_predios" -t "tabla_resultados_cabidas" | psql -d landengines -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres
