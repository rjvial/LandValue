using LandValue, DotEnv

codigo_predial = [151600217300085, 151600217300086, 151600217300087, 151600217300088, 151600217300089, 151600217300090, 151600217300091]

DotEnv.load("secrets.env")
datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
datos_mygis_db = ["gis_data", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
# datos_LandValue = ["landengines_local", "postgres", "", "localhost"]
# datos_mygis_db = ["gis_data_local", "postgres", "", "localhost"]

conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
conn_mygis_db = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])



display("Obtiene FlagPlotEdif3D")
@time df_flagplot = pg_julia.query(conn_LandValue, """SELECT * FROM public."tabla_flagplot_default";""")
fpe = FlagPlotEdif3D()
for field_s in fieldnames(FlagPlotEdif3D)
    value_ = df_flagplot[:, field_s][1]
    setproperty!(fpe, field_s, value_)
end

display("Obtiene DatosCabidaArquitectura")
@time df_arquitectura = pg_julia.query(conn_LandValue, """SELECT * FROM public."tabla_arquitectura_default";""")
dca = DatosCabidaArquitectura()
for field_s in fieldnames(DatosCabidaArquitectura)
    value_ = df_arquitectura[:, field_s][1]
    setproperty!(dca, field_s, value_)
end
alturaPiso = dca.alturaPiso


display("Generando Imagen de Cabida ")
display("")


codPredialStr = string(codigo_predial)

query_resultados = """
SELECT combi_predios, optimo_solucion, ps_predio, ps_vol_teorico, mat_conexion_vertices_vol_teorico,
"vecVertices_volTeorico", "ps_volConSombra", mat_conexion_vertices_con_sombra, vec_vertices_con_sombra,
ps_publico, ps_calles, ps_base, "ps_baseSeparada", "ps_primerPiso", ps_predios_intra_buffer, ps_manzanas_intra_buffer,
ps_calles_intra_buffer, id
FROM public.tabla_resultados_cabidas
WHERE combi_predios = \'$codPredialStr\'
"""
df_resultados = pg_julia.query(conn_LandValue, query_resultados)

codigo_predial = eval(Meta.parse(df_resultados[1, "combi_predios"]))
xopt = eval(Meta.parse(df_resultados[1, "optimo_solucion"]))
ps_predio = eval(Meta.parse(df_resultados[1, "ps_predio"]))
ps_volTeorico = eval(Meta.parse(df_resultados[1, "ps_vol_teorico"]))
matConexionVertices_volTeorico = eval(Meta.parse(df_resultados[1, "mat_conexion_vertices_vol_teorico"])) 
vecVertices_volTeorico = eval(Meta.parse(df_resultados[1, "vecVertices_volTeorico"]))
ps_volConSombra = eval(Meta.parse(df_resultados[1, "ps_volConSombra"]))
matConexionVertices_conSombra = eval(Meta.parse(df_resultados[1, "mat_conexion_vertices_con_sombra"]))
vecVertices_conSombra = eval(Meta.parse(df_resultados[1, "vec_vertices_con_sombra"]))
ps_publico = eval(Meta.parse(df_resultados[1, "ps_publico"]))
ps_calles = eval(Meta.parse(df_resultados[1, "ps_calles"]))
ps_base = eval(Meta.parse(df_resultados[1, "ps_base"]))
ps_baseSeparada = eval(Meta.parse(df_resultados[1, "ps_baseSeparada"]))
ps_primerPiso = eval(Meta.parse(df_resultados[1, "ps_primerPiso"]))
ps_predios_intra_buffer = eval(Meta.parse(df_resultados[1, "ps_predios_intra_buffer"]))
ps_manzanas_intra_buffer = eval(Meta.parse(df_resultados[1, "ps_manzanas_intra_buffer"]))
ps_calles_intra_buffer = eval(Meta.parse(df_resultados[1, "ps_calles_intra_buffer"]))
id = df_resultados[1, "id"]

fig, ax, ax_mat = polyShape.plotBaseEdificio3D(fpe, xopt, alturaPiso, ps_predio, ps_volTeorico, matConexionVertices_volTeorico, vecVertices_volTeorico, 
ps_volConSombra, matConexionVertices_conSombra, vecVertices_conSombra, ps_publico, ps_calles, ps_base, ps_baseSeparada, ps_primerPiso);

buffer_dist_ = min(140, 2.7474774194546216 * xopt[1] * alturaPiso)

ps_buffer_predio_ = polyShape.shapeBuffer(ps_predio, buffer_dist_, 20)
ps_predios_intra_buffer_ = polyShape.polyIntersect(ps_predios_intra_buffer, ps_buffer_predio_)
ps_manzanas_intra_buffer_ = polyShape.polyIntersect(ps_manzanas_intra_buffer, ps_buffer_predio_)

fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_predios_intra_buffer_, 0.0, "green", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_manzanas_intra_buffer_, 0.0, "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_buffer_predio_, 0.0, "gray", 0.15, fig=fig, ax=ax, ax_mat=ax_mat)
