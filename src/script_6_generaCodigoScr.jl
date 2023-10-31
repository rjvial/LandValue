using LandValue

conn_LandValue = pg_julia.connection("LandValue", "postgres", "postgres")


conn = conn_LandValue 

query_resultados_str = """
select * from tabla_resultados_cabidas ORDER BY id ASC;
"""
df_resultados = pg_julia.query(conn, query_resultados_str)


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

numRows, numCols = size(df_resultados)
rowSet = 1:numRows

# Agrega columna dir_image_file a tabla_resultados_cabidas
query_dir_image_str = """
ALTER TABLE tabla_resultados_cabidas
  ADD COLUMN IF NOT EXISTS dir_scr_file text;
"""
pg_julia.query(conn, query_dir_image_str)


for r in rowSet
    display("Generando Código Scr de Cabida N° = " * string(r))
    display("")

    codigo_predial = eval(Meta.parse(df_resultados[r, "combi_predios"]))
    temp_opt = df_resultados[r, "cabida_temp_opt"]
    numPisos = df_resultados[r, "cabida_num_pisos"]
    altura = df_resultados[r, "cabida_altura"]
    xopt = eval(Meta.parse(df_resultados[r, "optimo_solucion"]))
    ps_predio = eval(Meta.parse(df_resultados[r, "ps_predio"]))
    ps_volTeorico = eval(Meta.parse(df_resultados[r, "ps_vol_teorico"]))
    matConexionVertices_volTeorico = eval(Meta.parse(df_resultados[r, "mat_conexion_vertices_vol_teorico"])) 
    vecVertices_volTeorico = eval(Meta.parse(df_resultados[r, "vecVertices_volTeorico"]))
    ps_volConSombra = eval(Meta.parse(df_resultados[r, "ps_volConSombra"]))
    matConexionVertices_conSombra = eval(Meta.parse(df_resultados[r, "mat_conexion_vertices_con_sombra"]))
    vecVertices_conSombra = eval(Meta.parse(df_resultados[r, "vec_vertices_con_sombra"]))
    ps_publico = eval(Meta.parse(df_resultados[r, "ps_publico"]))
    ps_calles = eval(Meta.parse(df_resultados[r, "ps_calles"]))
    ps_base = eval(Meta.parse(df_resultados[r, "ps_base"]))
    ps_baseSeparada = eval(Meta.parse(df_resultados[r, "ps_baseSeparada"]))
    ps_predios_intra_buffer = eval(Meta.parse(df_resultados[r, "ps_predios_intra_buffer"]))
    ps_manzanas_intra_buffer = eval(Meta.parse(df_resultados[r, "ps_manzanas_intra_buffer"]))
    ps_calles_intra_buffer = eval(Meta.parse(df_resultados[r, "ps_calles_intra_buffer"]))
    id = df_resultados[r, "id"]
    
    filestr = "C:/Users/rjvia/.julia/dev/qgis_env/aux_files/codigos_scr/codigo_scr_vitacura_" * string(r) * ".scr"

    if conn == conn_LandValue
        fig, ax, ax_mat = polyShape.plotBaseEdificio3D(fpe, xopt, alturaPiso, ps_predio, ps_volTeorico, matConexionVertices_volTeorico, vecVertices_volTeorico, 
                                                ps_volConSombra, matConexionVertices_conSombra, vecVertices_conSombra, ps_publico, ps_calles, ps_base, ps_baseSeparada);

        buffer_dist_ = min(140, 2.7474774194546216 * xopt[1] * alturaPiso)

        ps_buffer_predio_ = polyShape.shapeBuffer(ps_predio, buffer_dist_, 20)
        ps_predios_intra_buffer_ = polyShape.polyIntersect(ps_predios_intra_buffer, ps_buffer_predio_)
        ps_manzanas_intra_buffer_ = polyShape.polyIntersect(ps_manzanas_intra_buffer, ps_buffer_predio_)

        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_predios_intra_buffer_, 0.0, "green", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_manzanas_intra_buffer_, 0.0, "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_buffer_predio_, 0.0, "gray", 0.15, fig=fig, ax=ax, ax_mat=ax_mat)

        create_scr(xopt, ps_predio, ps_base, alturaPiso, ps_volTeorico, matConexionVertices_volTeorico, vecVertices_volTeorico, filestr) 
        
        close("all")
    end

    executeStr = "UPDATE tabla_resultados_cabidas SET dir_scr_file = \'" * filestr * "\' WHERE combi_predios = \'" * df_resultados[r, "combi_predios"] * "\'"
    pg_julia.query(conn, executeStr)


end

