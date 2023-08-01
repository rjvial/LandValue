using LandValue, DotEnv, CSV

# Establece las conexiones a las Base de Datos
# conn_LandValue = pg_julia.connection("landengines", ENV["USER"], ENV["PW"], ENV["HOST"])

DotEnv.load("secrets.env") 
datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]

conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])


display("Obtiene DatosCabidaArquitectura")
@time df_arquitectura = pg_julia.query(conn_LandValue, """SELECT * FROM public."tabla_arquitectura_default";""")
dca = DatosCabidaArquitectura()
for field_s in fieldnames(DatosCabidaArquitectura)
    value_ = df_arquitectura[:, field_s][1]
    setproperty!(dca, field_s, value_)
end
alturaPiso = dca.alturaPiso

display("Obtiene listado de las combinaciones que con max gap para cada localidad")
query_max_gap = """
    SELECT id_combi_list, MAX(gap) AS max_gap,
    (SELECT id AS id_max_gap FROM tabla_resultados_cabidas t2 WHERE t2.id_combi_list = t1.id_combi_list AND t2.gap = MAX(t1.gap))
    FROM tabla_resultados_cabidas t1
    GROUP BY id_combi_list
    ORDER BY id_combi_list
"""
df_max_gap = pg_julia.query(conn_LandValue, query_max_gap)
vec_id = string(df_max_gap[:, "id_max_gap"])
list_max_gap = replace(replace(vec_id, "[" => "("), "]" => ")"  )

display("Obtiene datos de las combinaciones con max_gap para cada localidad")
query_max_localidad = """
    SELECT id, id_combi_list, gap, gap_porcentual
    FROM tabla_resultados_cabidas
    WHERE id IN $list_max_gap
"""
df_max_localidad = pg_julia.query(conn_LandValue, query_max_localidad)

display("Obtiene tabla combi_locations")
query_combi_locations = """
    SELECT * 
    FROM combi_locations
    ORDER BY id_combi_list ASC;
"""
df_combi_locations = pg_julia.query(conn_LandValue, query_combi_locations)

display("Agrega columnas a combi_locations")
query_add_columns = """
ALTER TABLE combi_locations
    ADD COLUMN IF NOT EXISTS id_max_gap integer,
    ADD COLUMN IF NOT EXISTS max_gap double precision,
    ADD COLUMN IF NOT EXISTS gap_porcentual double precision
"""
pg_julia.query(conn_LandValue, query_add_columns)

display("Agrega columnas a combi_locations")
for r in eachindex(df_combi_locations[:,"id_combi_list"])
    display("Agrega info de fila N°" * string(r) * " a la tabla combi_locations")
    val_id_max_gap = df_max_localidad[r, "id"]
    val_max_gap = df_max_localidad[r, "gap"]
    val_gap_porcentual = df_max_localidad[r, "gap_porcentual"]
    query_ = """
        UPDATE combi_locations SET id_max_gap = $val_id_max_gap, max_gap = $val_max_gap, gap_porcentual = $val_gap_porcentual
        WHERE id_combi_list = $r
        """
    pg_julia.query(conn_LandValue, query_)
end


query_resultados_str = """
    SELECT * 
    FROM tabla_resultados_cabidas
    WHERE id IN $list_max_gap
    ORDER BY id ASC;
"""
df_resultados_max_gap = pg_julia.query(conn_LandValue, query_resultados_str)


query_gap_total_str = """
    SELECT SUM(gap) 
    FROM tabla_resultados_cabidas
    WHERE id IN $list_max_gap
"""
gap_total = pg_julia.query(conn_LandValue, query_gap_total_str)[:,1][1]
display("Gap Total: " * string(gap_total))

query_num_total_str = """
    SELECT count(gap)
    FROM tabla_resultados_cabidas
    WHERE id IN $list_max_gap
"""
gap_num_total = pg_julia.query(conn_LandValue, query_num_total_str)[:,1][1]
display("Num Localidades: " * string(gap_num_total))

query_gap_positivo_str = """
    SELECT SUM(gap) 
    FROM tabla_resultados_cabidas
    WHERE id IN $list_max_gap AND gap > 0
"""
gap_positivo = pg_julia.query(conn_LandValue, query_gap_positivo_str)[:,1][1]
display("Gap Total Positivo: " * string(gap_positivo))

query_num_pos_str = """
    SELECT count(gap)
    FROM tabla_resultados_cabidas
    WHERE id IN $list_max_gap AND gap > 0
"""
gap_num_pos = pg_julia.query(conn_LandValue, query_num_pos_str)[:,1][1]
display("Num Localidades Positivas: " * string(gap_num_pos))

query_gap_negativo_str = """
    SELECT SUM(gap) 
    FROM tabla_resultados_cabidas
    WHERE id IN $list_max_gap AND gap < 0
"""
gap_negativo = pg_julia.query(conn_LandValue, query_gap_negativo_str)[:,1][1]
display("Gap Total Negativo: " * string(gap_negativo))

query_num_neg_str = """
    SELECT count(gap)
    FROM tabla_resultados_cabidas
    WHERE id IN $list_max_gap AND gap < 0
"""
gap_num_neg = pg_julia.query(conn_LandValue, query_num_neg_str)[:,1][1]
display("Num Localidades Negativas: " * string(gap_num_neg))

query_holgura_cont_str = """
    SELECT SUM(holgura_constructibilidad) 
    FROM tabla_resultados_cabidas
    WHERE id IN $list_max_gap 
"""
holgura_const_total = pg_julia.query(conn_LandValue, query_holgura_cont_str)[:,1][1]/gap_num_total
display("Holgura Constructibilidad Total: " * string(holgura_const_total))

query_holgura_cont_pos_str = """
    SELECT SUM(holgura_constructibilidad) 
    FROM tabla_resultados_cabidas
    WHERE id IN $list_max_gap AND gap > 0
"""
holgura_const_pos = pg_julia.query(conn_LandValue, query_holgura_cont_pos_str)[:,1][1]/gap_num_pos
display("Holgura Constructibilidad Positivas: " * string(holgura_const_pos))

query_holgura_cont_neg_str = """
    SELECT SUM(holgura_constructibilidad) 
    FROM tabla_resultados_cabidas
    WHERE id IN $list_max_gap AND gap < 0
"""
holgura_const_neg = pg_julia.query(conn_LandValue, query_holgura_cont_neg_str)[:,1][1]/gap_num_neg
display("Holgura Constructibilidad Negativas: " * string(holgura_const_neg))

query_sup_edif_total_str = """
    SELECT SUM(cabida_superficie_edificada_snt) 
    FROM tabla_resultados_cabidas
    WHERE id IN $list_max_gap
"""
sup_edif_total = pg_julia.query(conn_LandValue, query_sup_edif_total_str)[:,1][1]
display("Superficie Edificada Total: " * string(sup_edif_total))

query_sup_edif_pos_str = """
    SELECT SUM(cabida_superficie_edificada_snt) 
    FROM tabla_resultados_cabidas
    WHERE id IN $list_max_gap AND gap > 0
"""
sup_edif_pos = pg_julia.query(conn_LandValue, query_sup_edif_pos_str)[:,1][1]
display("Superficie Edificada Positivas: " * string(sup_edif_pos))

query_sup_edif_neg_str = """
    SELECT SUM(cabida_superficie_edificada_snt) 
    FROM tabla_resultados_cabidas
    WHERE id IN $list_max_gap AND gap < 0
"""
sup_edif_neg = pg_julia.query(conn_LandValue, query_sup_edif_neg_str)[:,1][1]
display("Superficie Edificada Negativas: " * string(sup_edif_neg))

query_sup_terreno_pos_str = """
    SELECT SUM(terreno_superficie) 
    FROM tabla_resultados_cabidas
    WHERE id IN $list_max_gap AND gap > 0
"""
sup_terreno_pos = pg_julia.query(conn_LandValue, query_sup_terreno_pos_str)[:,1][1]
display("Superficie Terreno Positivas: " * string(sup_terreno_pos))




query_ = """
    SELECT ST_AsGeoJSON(subq.*) AS geojson
    FROM (
    SELECT ST_Centroid(geom_combi),
        combi_predios,
        norma_max_num_deptos,
        norma_max_ocupacion,
        norma_max_constructibilidad,
        norma_max_pisos,
        norma_max_altura,
        norma_min_estacionamientos_vendibles,
        norma_min_estacionamientos_visita,
        norma_min_estacionamientos_discapacitados,
        cabida_temp_opt,
        cabida_tipo_deptos,
        cabida_num_deptos,
        cabida_ocupacion,
        cabida_constructibilidad,
        cabida_num_pisos,
        cabida_altura,
        cabida_superficie_interior,
        cabida_superficie_terraza,
        cabida_superficie_comun,
        cabida_superficie_edificada_snt,
        cabida_superficie_por_piso,
        cabida_estacionamientos_vendibles,
        cabida_estacionamientos_visita,
        cabida_num_estacionamientos,
        cabida_num_bicicleteros,
        cabida_num_bodegas,
        terreno_superficie,
        terreno_superficie_bruta,
        "terreno_largoFrenteCalle",
        terreno_costo,
        terreno_costo_unit,
        terreno_costo_corredor,
        terreno_costo_demolicion,
        terreno_otros,
        terreno_costo_total,
        terreno_costo_unit_total,
        holgura_ocupacion,
        holgura_constructibilidad,
        holgura_densidad,
        indicador_ingresos_ventas,
        indicador_costo_total,
        indicador_margen_antes_impuesto,
        indicador_impuesto_renta,
        indicador_utilidad_despues_impuesto,
        indicador_rentabilidad_total_bruta,
        indicador_rentabilidad_total_neta,
        indicador_incidencia_terreno,
        optimo_solucion,
        id,
        dir_image_file,
        id_combi_list,
        valor_combi,
        gap,
        gap_porcentual

    FROM tabla_resultados_cabidas
        WHERE id IN $list_max_gap
    ) AS subq
"""

df_resultados_cabidas = pg_julia.query(conn_LandValue, query_)

numfilas = size(df_resultados_cabidas,1)
json_str = """
{
    "type": "FeatureCollection",
    "crs": {
        "type": "name",
        "properties": {
            "name": "urn:ogc:def:crs:OGC:1.3:CRS84"
        }
    },
    "features": [
"""
for i in 1:numfilas
    if i == numfilas
        row_str_i = df_resultados_cabidas[i,"geojson"] * "]}"
    else
        row_str_i = df_resultados_cabidas[i,"geojson"] * ","
    end
    json_str = json_str * row_str_i
end


open("C:\\Users\\rjvia\\Documents\\Land_engines_code\\Julia\\resultados_cabidas.json", "w") do file
    write(file, json_str)
end

