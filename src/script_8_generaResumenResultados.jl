using LandValue

conn_LandValue = pg_julia.connection("landengines", ENV["USER"], ENV["PW"], ENV["HOST"])
conn = conn_LandValue 

display("Obtiene DatosCabidaArquitectura")
@time df_arquitectura = pg_julia.query(conn_LandValue, """SELECT * FROM public."tabla_arquitectura_default";""")
dca = DatosCabidaArquitectura()
for field_s in fieldnames(DatosCabidaArquitectura)
    value_ = df_arquitectura[:, field_s][1]
    setproperty!(dca, field_s, value_)
end
alturaPiso = dca.alturaPiso

query_resultados_str = """
    SELECT * 
    FROM tabla_resultados_cabidas
    WHERE id IN (1,2,3,4,5,8,15,20,27,29,34,35,36,40,42,43,44,49,58,59,62,63,66,82,88,93,94,95,100,105,108,109,114,121,131,144,147,163,168,174,176,178,181,197,201,207,208,253,263,264,266,275,277,280,281,289,317,323,326,327,335,352,379,380,386,387,388,391,399,405,409,410,415,439,443,486,493,494,497,500,502,514,521,535,542,545,549,571,578,584,590,603,637,646,671,672,673)
    ORDER BY id ASC;
"""
df_resultados = pg_julia.query(conn, query_resultados_str)


query_gap_total_str = """
    SELECT SUM(gap) 
    FROM tabla_resultados_cabidas
    WHERE id IN (1,2,3,4,5,8,15,20,27,29,34,35,36,40,42,43,44,49,58,59,62,63,66,82,88,93,94,95,100,105,108,109,114,121,131,144,147,163,168,174,176,178,181,197,201,207,208,253,263,264,266,275,277,280,281,289,317,323,326,327,335,352,379,380,386,387,388,391,399,405,409,410,415,439,443,486,493,494,497,500,502,514,521,535,542,545,549,571,578,584,590,603,637,646,671,672,673)
"""
gap_total = pg_julia.query(conn, query_gap_total_str)[:,1][1]
query_num_total_str = """
    SELECT count(gap)
    FROM tabla_resultados_cabidas
    WHERE id IN (1,2,3,4,5,8,15,20,27,29,34,35,36,40,42,43,44,49,58,59,62,63,66,82,88,93,94,95,100,105,108,109,114,121,131,144,147,163,168,174,176,178,181,197,201,207,208,253,263,264,266,275,277,280,281,289,317,323,326,327,335,352,379,380,386,387,388,391,399,405,409,410,415,439,443,486,493,494,497,500,502,514,521,535,542,545,549,571,578,584,590,603,637,646,671,672,673)
"""
gap_num_total = pg_julia.query(conn, query_num_total_str)[:,1][1]


query_gap_positivo_str = """
    SELECT SUM(gap) 
    FROM tabla_resultados_cabidas
    WHERE id IN (1,2,3,4,5,8,15,20,27,29,34,35,36,40,42,43,44,49,58,59,62,63,66,82,88,93,94,95,100,105,108,109,114,121,131,144,147,163,168,174,176,178,181,197,201,207,208,253,263,264,266,275,277,280,281,289,317,323,326,327,335,352,379,380,386,387,388,391,399,405,409,410,415,439,443,486,493,494,497,500,502,514,521,535,542,545,549,571,578,584,590,603,637,646,671,672,673) AND gap > 0
"""
gap_positivo = pg_julia.query(conn, query_gap_positivo_str)[:,1][1]
query_num_pos_str = """
    SELECT count(gap)
    FROM tabla_resultados_cabidas
    WHERE id IN (1,2,3,4,5,8,15,20,27,29,34,35,36,40,42,43,44,49,58,59,62,63,66,82,88,93,94,95,100,105,108,109,114,121,131,144,147,163,168,174,176,178,181,197,201,207,208,253,263,264,266,275,277,280,281,289,317,323,326,327,335,352,379,380,386,387,388,391,399,405,409,410,415,439,443,486,493,494,497,500,502,514,521,535,542,545,549,571,578,584,590,603,637,646,671,672,673) AND gap > 0
"""
gap_num_pos = pg_julia.query(conn, query_num_pos_str)[:,1][1]

query_gap_negativo_str = """
    SELECT SUM(gap) 
    FROM tabla_resultados_cabidas
    WHERE id IN (1,2,3,4,5,8,15,20,27,29,34,35,36,40,42,43,44,49,58,59,62,63,66,82,88,93,94,95,100,105,108,109,114,121,131,144,147,163,168,174,176,178,181,197,201,207,208,253,263,264,266,275,277,280,281,289,317,323,326,327,335,352,379,380,386,387,388,391,399,405,409,410,415,439,443,486,493,494,497,500,502,514,521,535,542,545,549,571,578,584,590,603,637,646,671,672,673) AND gap < 0
"""
gap_negativo = pg_julia.query(conn, query_gap_negativo_str)[:,1][1]
query_num_neg_str = """
    SELECT count(gap)
    FROM tabla_resultados_cabidas
    WHERE id IN (1,2,3,4,5,8,15,20,27,29,34,35,36,40,42,43,44,49,58,59,62,63,66,82,88,93,94,95,100,105,108,109,114,121,131,144,147,163,168,174,176,178,181,197,201,207,208,253,263,264,266,275,277,280,281,289,317,323,326,327,335,352,379,380,386,387,388,391,399,405,409,410,415,439,443,486,493,494,497,500,502,514,521,535,542,545,549,571,578,584,590,603,637,646,671,672,673) AND gap < 0
"""
gap_num_neg = pg_julia.query(conn, query_num_neg_str)[:,1][1]

query_holgura_cont_str = """
    SELECT SUM(holgura_constructibilidad) 
    FROM tabla_resultados_cabidas
    WHERE id IN (1,2,3,4,5,8,15,20,27,29,34,35,36,40,42,43,44,49,58,59,62,63,66,82,88,93,94,95,100,105,108,109,114,121,131,144,147,163,168,174,176,178,181,197,201,207,208,253,263,264,266,275,277,280,281,289,317,323,326,327,335,352,379,380,386,387,388,391,399,405,409,410,415,439,443,486,493,494,497,500,502,514,521,535,542,545,549,571,578,584,590,603,637,646,671,672,673) 
"""
holgura_const_total = pg_julia.query(conn, query_holgura_cont_str)[:,1][1]/gap_num_total

query_holgura_cont_pos_str = """
    SELECT SUM(holgura_constructibilidad) 
    FROM tabla_resultados_cabidas
    WHERE id IN (1,2,3,4,5,8,15,20,27,29,34,35,36,40,42,43,44,49,58,59,62,63,66,82,88,93,94,95,100,105,108,109,114,121,131,144,147,163,168,174,176,178,181,197,201,207,208,253,263,264,266,275,277,280,281,289,317,323,326,327,335,352,379,380,386,387,388,391,399,405,409,410,415,439,443,486,493,494,497,500,502,514,521,535,542,545,549,571,578,584,590,603,637,646,671,672,673) AND gap > 0
"""
holgura_const_pos = pg_julia.query(conn, query_holgura_cont_pos_str)[:,1][1]/gap_num_pos

query_holgura_cont_neg_str = """
    SELECT SUM(holgura_constructibilidad) 
    FROM tabla_resultados_cabidas
    WHERE id IN (1,2,3,4,5,8,15,20,27,29,34,35,36,40,42,43,44,49,58,59,62,63,66,82,88,93,94,95,100,105,108,109,114,121,131,144,147,163,168,174,176,178,181,197,201,207,208,253,263,264,266,275,277,280,281,289,317,323,326,327,335,352,379,380,386,387,388,391,399,405,409,410,415,439,443,486,493,494,497,500,502,514,521,535,542,545,549,571,578,584,590,603,637,646,671,672,673) AND gap > 0
"""
holgura_const_neg = pg_julia.query(conn, query_holgura_cont_neg_str)[:,1][1]/gap_num_neg

query_sup_edif_total_str = """
    SELECT SUM(cabida_superficie_edificada_snt) 
    FROM tabla_resultados_cabidas
    WHERE id IN (1,2,3,4,5,8,15,20,27,29,34,35,36,40,42,43,44,49,58,59,62,63,66,82,88,93,94,95,100,105,108,109,114,121,131,144,147,163,168,174,176,178,181,197,201,207,208,253,263,264,266,275,277,280,281,289,317,323,326,327,335,352,379,380,386,387,388,391,399,405,409,410,415,439,443,486,493,494,497,500,502,514,521,535,542,545,549,571,578,584,590,603,637,646,671,672,673)
"""
sup_edif_total = pg_julia.query(conn, query_sup_edif_total_str)[:,1][1]

query_sup_edif_pos_str = """
    SELECT SUM(cabida_superficie_edificada_snt) 
    FROM tabla_resultados_cabidas
    WHERE id IN (1,2,3,4,5,8,15,20,27,29,34,35,36,40,42,43,44,49,58,59,62,63,66,82,88,93,94,95,100,105,108,109,114,121,131,144,147,163,168,174,176,178,181,197,201,207,208,253,263,264,266,275,277,280,281,289,317,323,326,327,335,352,379,380,386,387,388,391,399,405,409,410,415,439,443,486,493,494,497,500,502,514,521,535,542,545,549,571,578,584,590,603,637,646,671,672,673) AND gap > 0
"""
sup_edif_pos = pg_julia.query(conn, query_sup_edif_pos_str)[:,1][1]

query_sup_edif_neg_str = """
    SELECT SUM(cabida_superficie_edificada_snt) 
    FROM tabla_resultados_cabidas
    WHERE id IN (1,2,3,4,5,8,15,20,27,29,34,35,36,40,42,43,44,49,58,59,62,63,66,82,88,93,94,95,100,105,108,109,114,121,131,144,147,163,168,174,176,178,181,197,201,207,208,253,263,264,266,275,277,280,281,289,317,323,326,327,335,352,379,380,386,387,388,391,399,405,409,410,415,439,443,486,493,494,497,500,502,514,521,535,542,545,549,571,578,584,590,603,637,646,671,672,673) AND gap < 0
"""
sup_edif_neg = pg_julia.query(conn, query_sup_edif_neg_str)[:,1][1]

query_sup_terreno_pos_str = """
    SELECT SUM(terreno_superficie) 
    FROM tabla_resultados_cabidas
    WHERE id IN (1,2,3,4,5,8,15,20,27,29,34,35,36,40,42,43,44,49,58,59,62,63,66,82,88,93,94,95,100,105,108,109,114,121,131,144,147,163,168,174,176,178,181,197,201,207,208,253,263,264,266,275,277,280,281,289,317,323,326,327,335,352,379,380,386,387,388,391,399,405,409,410,415,439,443,486,493,494,497,500,502,514,521,535,542,545,549,571,578,584,590,603,637,646,671,672,673) AND gap > 0
"""
sup_terreno_pos = pg_julia.query(conn, query_sup_terreno_pos_str)[:,1][1]


numRows, numCols = size(df_resultados)
rowSet = 1:numRows

norma_max_num_deptos = []
norma_max_ocupacion = []
norma_max_constructibilidad = []
norma_max_pisos = []
norma_max_altura = []
norma_min_estacionamientos_vendibles = []
norma_min_estacionamientos_visita = []
norma_min_estacionamientos_discapacitados = []
cabida_temp_opt = []
cabida_tipo_deptos = []
cabida_num_deptos = []
cabida_ocupacion = []
cabida_constructibilidad = []
cabida_num_pisos = []
cabida_altura = []
cabida_superficie_interior = []
cabida_superficie_terraza = []
cabida_superficie_comun = []
cabida_superficie_edificada_snt = []
cabida_superficie_por_piso = []
cabida_estacionamientos_vendibles = []
cabida_estacionamientos_visita = []
cabida_num_estacionamientos = []
cabida_num_bicicleteros = []
cabida_num_bodegas = []
terreno_superficie = []
terreno_superficie_bruta = []
terreno_largoFrenteCalle = []
terreno_costo = []
terreno_costo_unit = []
terreno_costo_corredor = []
terreno_costo_demolicion = []
terreno_otros = []
terreno_costo_total = []
terreno_costo_unit_total = []
holgura_ocupacion = []
holgura_constructibilidad = []
holgura_densidad = []
indicador_ingresos_ventas = []
indicador_costo_total = []
indicador_margen_antes_impuesto = []
indicador_impuesto_renta = []
indicador_utilidad_despues_impuesto = []
indicador_rentabilidad_total_bruta = []
indicador_rentabilidad_total_neta = []
indicador_incidencia_terreno = []
optimo_solucion = []
id = []
id_combi = []
valor_combi = []
gap = []
gap_porcentual = []


for r in rowSet
    display("Generando: " * string(r))
    display("")

    push!(norma_max_num_deptos, df_resultados[r, "norma_max_num_deptos"])
    push!(norma_max_ocupacion, df_resultados[r, "norma_max_ocupacion"])
    push!(norma_max_constructibilidad, df_resultados[r, "norma_max_constructibilidad"])
    push!(norma_max_pisos , df_resultados[r, "norma_max_pisos"])
    push!(norma_max_altura , df_resultados[r, "norma_max_altura"])
    push!(norma_min_estacionamientos_vendibles , df_resultados[r, "norma_min_estacionamientos_vendibles"])
    push!(norma_min_estacionamientos_visita , df_resultados[r, "norma_min_estacionamientos_visita"])
    push!(norma_min_estacionamientos_discapacitados , df_resultados[r, "norma_min_estacionamientos_discapacitados"])
    push!(cabida_temp_opt, df_resultados[r, "cabida_temp_opt"])
    push!(cabida_tipo_deptos, df_resultados[r, "cabida_tipo_deptos"])
    if df_resultados[r, "cabida_num_deptos"] != ""
        push!(cabida_num_deptos,  sum(eval(Meta.parse((replace(df_resultados[r, "cabida_num_deptos"], ", ]" => "]"))))))
    else
        push!(cabida_num_deptos,  0)
    end
    push!(cabida_ocupacion , df_resultados[r, "cabida_ocupacion"])
    push!(cabida_constructibilidad , df_resultados[r, "cabida_constructibilidad"])
    push!(cabida_num_pisos , df_resultados[r, "cabida_num_pisos"])
    push!(cabida_altura , df_resultados[r, "cabida_altura"])
    push!(cabida_superficie_interior , df_resultados[r, "cabida_superficie_interior"])
    push!(cabida_superficie_terraza , df_resultados[r, "cabida_superficie_terraza"])
    push!(cabida_superficie_comun , df_resultados[r, "cabida_superficie_comun"])
    push!(cabida_superficie_edificada_snt , df_resultados[r, "cabida_superficie_edificada_snt"])
    push!(cabida_superficie_por_piso , df_resultados[r, "cabida_superficie_por_piso"])
    push!(cabida_estacionamientos_vendibles , df_resultados[r, "cabida_estacionamientos_vendibles"])
    push!(cabida_estacionamientos_visita , df_resultados[r, "cabida_estacionamientos_visita"])
    push!(cabida_num_estacionamientos , df_resultados[r, "cabida_num_estacionamientos"])
    push!(cabida_num_bicicleteros , df_resultados[r, "cabida_num_bicicleteros"])
    push!(cabida_num_bodegas , df_resultados[r, "cabida_num_bodegas"])
    push!(terreno_superficie , df_resultados[r, "terreno_superficie"])
    push!(terreno_superficie_bruta , df_resultados[r, "terreno_superficie_bruta"])
    push!(terreno_largoFrenteCalle , df_resultados[r, "terreno_largoFrenteCalle"])
    push!(terreno_costo , df_resultados[r, "terreno_costo"])
    push!(terreno_costo_unit , df_resultados[r, "terreno_costo_unit"])
    push!(terreno_costo_corredor , df_resultados[r, "terreno_costo_corredor"])
    push!(terreno_costo_demolicion , df_resultados[r, "terreno_costo_demolicion"])
    push!(terreno_otros , df_resultados[r, "terreno_otros"])
    push!(terreno_costo_total , df_resultados[r, "terreno_costo_total"])
    push!(terreno_costo_unit_total , df_resultados[r, "terreno_costo_unit_total"])
    push!(holgura_ocupacion , df_resultados[r, "holgura_ocupacion"])
    push!(holgura_constructibilidad , df_resultados[r, "holgura_constructibilidad"])
    push!(holgura_densidad , df_resultados[r, "holgura_densidad"])
    push!(indicador_ingresos_ventas , df_resultados[r, "indicador_ingresos_ventas"])
    push!(indicador_costo_total , df_resultados[r, "indicador_costo_total"])
    push!(indicador_margen_antes_impuesto , df_resultados[r, "indicador_margen_antes_impuesto"])
    push!(indicador_impuesto_renta , df_resultados[r, "indicador_impuesto_renta"])
    push!(indicador_utilidad_despues_impuesto , df_resultados[r, "indicador_utilidad_despues_impuesto"])
    push!(indicador_rentabilidad_total_bruta , df_resultados[r, "indicador_rentabilidad_total_bruta"])
    push!(indicador_rentabilidad_total_neta , df_resultados[r, "indicador_rentabilidad_total_neta"])
    push!(indicador_incidencia_terreno , df_resultados[r, "indicador_incidencia_terreno"])
    push!(optimo_solucion, df_resultados[r, "optimo_solucion"])
    push!(id, df_resultados[r, "id"])
    push!(id_combi, df_resultados[r, "id_combi"])
    push!(valor_combi , df_resultados[r, "valor_combi"])
    push!(gap , df_resultados[r, "gap"])
    push!(gap_porcentual , df_resultados[r, "gap_porcentual"])

end

num_depts_pos = sum(cabida_num_deptos[gap .> 0])
