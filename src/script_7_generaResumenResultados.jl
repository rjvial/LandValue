using LandValue, DotEnv

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
    ADD COLUMN IF NOT EXISTS max_gap double precision
"""
pg_julia.query(conn_LandValue, query_add_columns)

display("Agrega columnas a combi_locations")
for r in eachindex(df_combi_locations[:,"id_combi_list"])
    display("Agrega info de fila N°" * string(r) * " a la tabla combi_locations")
    val_id_max_gap = df_max_gap[r, "id_max_gap"]
    val_max_gap = df_max_gap[r, "max_gap"]
    query_ = """
        UPDATE combi_locations SET id_max_gap = $val_id_max_gap, max_gap = $val_max_gap
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

# numRows, numCols = size(df_resultados_max_gap)
# rowSet = 1:numRows

# norma_max_num_deptos = []
# norma_max_ocupacion = []
# norma_max_constructibilidad = []
# norma_max_pisos = []
# norma_max_altura = []
# norma_min_estacionamientos_vendibles = []
# norma_min_estacionamientos_visita = []
# norma_min_estacionamientos_discapacitados = []
# cabida_temp_opt = []
# cabida_tipo_deptos = []
# cabida_num_deptos = []
# cabida_ocupacion = []
# cabida_constructibilidad = []
# cabida_num_pisos = []
# cabida_altura = []
# cabida_superficie_interior = []
# cabida_superficie_terraza = []
# cabida_superficie_comun = []
# cabida_superficie_edificada_snt = []
# cabida_superficie_por_piso = []
# cabida_estacionamientos_vendibles = []
# cabida_estacionamientos_visita = []
# cabida_num_estacionamientos = []
# cabida_num_bicicleteros = []
# cabida_num_bodegas = []
# terreno_superficie = []
# terreno_superficie_bruta = []
# terreno_largoFrenteCalle = []
# terreno_costo = []
# terreno_costo_unit = []
# terreno_costo_corredor = []
# terreno_costo_demolicion = []
# terreno_otros = []
# terreno_costo_total = []
# terreno_costo_unit_total = []
# holgura_ocupacion = []
# holgura_constructibilidad = []
# holgura_densidad = []
# indicador_ingresos_ventas = []
# indicador_costo_total = []
# indicador_margen_antes_impuesto = []
# indicador_impuesto_renta = []
# indicador_utilidad_despues_impuesto = []
# indicador_rentabilidad_total_bruta = []
# indicador_rentabilidad_total_neta = []
# indicador_incidencia_terreno = []
# optimo_solucion = []
# id = []
# id_combi_list = []
# valor_combi = []
# gap = []
# gap_porcentual = []


# for r in rowSet
#     display("Generando: " * string(r))
#     display("")

#     push!(norma_max_num_deptos, df_resultados_max_gap[r, "norma_max_num_deptos"])
#     push!(norma_max_ocupacion, df_resultados_max_gap[r, "norma_max_ocupacion"])
#     push!(norma_max_constructibilidad, df_resultados_max_gap[r, "norma_max_constructibilidad"])
#     push!(norma_max_pisos , df_resultados_max_gap[r, "norma_max_pisos"])
#     push!(norma_max_altura , df_resultados_max_gap[r, "norma_max_altura"])
#     push!(norma_min_estacionamientos_vendibles , df_resultados_max_gap[r, "norma_min_estacionamientos_vendibles"])
#     push!(norma_min_estacionamientos_visita , df_resultados_max_gap[r, "norma_min_estacionamientos_visita"])
#     push!(norma_min_estacionamientos_discapacitados , df_resultados_max_gap[r, "norma_min_estacionamientos_discapacitados"])
#     push!(cabida_temp_opt, df_resultados_max_gap[r, "cabida_temp_opt"])
#     push!(cabida_tipo_deptos, df_resultados_max_gap[r, "cabida_tipo_deptos"])
#     if df_resultados_max_gap[r, "cabida_num_deptos"] != ""
#         push!(cabida_num_deptos,  sum(eval(Meta.parse((replace(df_resultados_max_gap[r, "cabida_num_deptos"], ", ]" => "]"))))))
#     else
#         push!(cabida_num_deptos,  0)
#     end
#     push!(cabida_ocupacion , df_resultados_max_gap[r, "cabida_ocupacion"])
#     push!(cabida_constructibilidad , df_resultados_max_gap[r, "cabida_constructibilidad"])
#     push!(cabida_num_pisos , df_resultados_max_gap[r, "cabida_num_pisos"])
#     push!(cabida_altura , df_resultados_max_gap[r, "cabida_altura"])
#     push!(cabida_superficie_interior , df_resultados_max_gap[r, "cabida_superficie_interior"])
#     push!(cabida_superficie_terraza , df_resultados_max_gap[r, "cabida_superficie_terraza"])
#     push!(cabida_superficie_comun , df_resultados_max_gap[r, "cabida_superficie_comun"])
#     push!(cabida_superficie_edificada_snt , df_resultados_max_gap[r, "cabida_superficie_edificada_snt"])
#     push!(cabida_superficie_por_piso , df_resultados_max_gap[r, "cabida_superficie_por_piso"])
#     push!(cabida_estacionamientos_vendibles , df_resultados_max_gap[r, "cabida_estacionamientos_vendibles"])
#     push!(cabida_estacionamientos_visita , df_resultados_max_gap[r, "cabida_estacionamientos_visita"])
#     push!(cabida_num_estacionamientos , df_resultados_max_gap[r, "cabida_num_estacionamientos"])
#     push!(cabida_num_bicicleteros , df_resultados_max_gap[r, "cabida_num_bicicleteros"])
#     push!(cabida_num_bodegas , df_resultados_max_gap[r, "cabida_num_bodegas"])
#     push!(terreno_superficie , df_resultados_max_gap[r, "terreno_superficie"])
#     push!(terreno_superficie_bruta , df_resultados_max_gap[r, "terreno_superficie_bruta"])
#     push!(terreno_largoFrenteCalle , df_resultados_max_gap[r, "terreno_largoFrenteCalle"])
#     push!(terreno_costo , df_resultados_max_gap[r, "terreno_costo"])
#     push!(terreno_costo_unit , df_resultados_max_gap[r, "terreno_costo_unit"])
#     push!(terreno_costo_corredor , df_resultados_max_gap[r, "terreno_costo_corredor"])
#     push!(terreno_costo_demolicion , df_resultados_max_gap[r, "terreno_costo_demolicion"])
#     push!(terreno_otros , df_resultados_max_gap[r, "terreno_otros"])
#     push!(terreno_costo_total , df_resultados_max_gap[r, "terreno_costo_total"])
#     push!(terreno_costo_unit_total , df_resultados_max_gap[r, "terreno_costo_unit_total"])
#     push!(holgura_ocupacion , df_resultados_max_gap[r, "holgura_ocupacion"])
#     push!(holgura_constructibilidad , df_resultados_max_gap[r, "holgura_constructibilidad"])
#     push!(holgura_densidad , df_resultados_max_gap[r, "holgura_densidad"])
#     push!(indicador_ingresos_ventas , df_resultados_max_gap[r, "indicador_ingresos_ventas"])
#     push!(indicador_costo_total , df_resultados_max_gap[r, "indicador_costo_total"])
#     push!(indicador_margen_antes_impuesto , df_resultados_max_gap[r, "indicador_margen_antes_impuesto"])
#     push!(indicador_impuesto_renta , df_resultados_max_gap[r, "indicador_impuesto_renta"])
#     push!(indicador_utilidad_despues_impuesto , df_resultados_max_gap[r, "indicador_utilidad_despues_impuesto"])
#     push!(indicador_rentabilidad_total_bruta , df_resultados_max_gap[r, "indicador_rentabilidad_total_bruta"])
#     push!(indicador_rentabilidad_total_neta , df_resultados_max_gap[r, "indicador_rentabilidad_total_neta"])
#     push!(indicador_incidencia_terreno , df_resultados_max_gap[r, "indicador_incidencia_terreno"])
#     push!(optimo_solucion, df_resultados_max_gap[r, "optimo_solucion"])
#     push!(id, df_resultados_max_gap[r, "id"])
#     push!(id_combi_list, df_resultados_max_gap[r, "id_combi_list"])
#     push!(valor_combi , df_resultados_max_gap[r, "valor_combi"])
#     push!(gap , df_resultados_max_gap[r, "gap"])
#     push!(gap_porcentual , df_resultados_max_gap[r, "gap_porcentual"])

# end

# num_depts_pos = sum(cabida_num_deptos[gap .> 0])
