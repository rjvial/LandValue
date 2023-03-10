using LandValue

conn_LandValue = pg_julia.connection("LandValue", "postgres", "postgres")

query_resultados_str = """
select * from tabla_resultados_cabidas ORDER BY id ASC
"""
df_resultados = pg_julia.query(conn_LandValue, query_resultados_str)


# # Guarda resultados en archivos csv y xlsx
# outfileStr = "C:/Users/rjvia/.julia/dev/ws/resultados_cabida/resultadoCabida.csv"
# pg_julia.df2csv(df_resultados, outfileStr)



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
  ADD COLUMN IF NOT EXISTS dir_image_file text;
"""
pg_julia.query(conn_LandValue, query_dir_image_str)


for r in rowSet
    display("Generando Imagen de Cabida N° = " * string(r))
    display("")

    codigo_predial = eval(Meta.parse(df_resultados[r, "combi_predios"]))
    maxNumDeptos = df_resultados[r, "norma_max_num_deptos"]
    maxOcupacion = df_resultados[r, "norma_max_ocupacion"]
    maxConstructibilidad = df_resultados[r, "norma_max_constructibilidad"]
    maxPisos = df_resultados[r, "norma_max_pisos"]
    maxAltura = df_resultados[r, "norma_max_altura"]
    minEstacionamientosVendibles = df_resultados[r, "norma_min_estacionamientos_vendibles"]
    minEstacionamientosVisita = df_resultados[r, "norma_min_estacionamientos_visita"]
    minEstacionamientosDiscapacitados = df_resultados[r, "norma_min_estacionamientos_discapacitados"]
    temp_opt = df_resultados[r, "cabida_temp_opt"]
    numDeptos = df_resultados[r, "cabida_num_deptos"]
    ocupacion = df_resultados[r, "cabida_ocupacion"]
    constructibilidad = df_resultados[r, "cabida_constructibilidad"]
    numPisos = df_resultados[r, "cabida_num_pisos"]
    altura = df_resultados[r, "cabida_altura"]
    superficieInterior = df_resultados[r, "cabida_superficie_interior"]
    superficieTerraza = df_resultados[r, "cabida_superficie_terraza"]
    superficieComun = df_resultados[r, "cabida_superficie_comun"]
    superficieEdificadaSNT = df_resultados[r, "cabida_superficie_edificada_snt"]
    superficiePorPiso = df_resultados[r, "cabida_superficie_por_piso"]
    estacionamientosVendibles = df_resultados[r, "cabida_estacionamientos_vendibles"]
    estacionamientosVisita = df_resultados[r, "cabida_estacionamientos_visita"]
    numEstacionamientos = df_resultados[r, "cabida_num_estacionamientos"]
    numBicicleteros = df_resultados[r, "cabida_num_bicicleteros"]
    numBodegas = df_resultados[r, "cabida_num_bodegas"]
    superficieTerreno = df_resultados[r, "terreno_superficie"]
    superficieBruta = df_resultados[r, "terreno_superficie_bruta"]
    largoFrenteCalle = df_resultados[r, "terreno_largoFrenteCalle"]
    costoTerreno = df_resultados[r, "terreno_costo"]
    costoUnitTerreno = df_resultados[r, "terreno_costo_unit"]
    costoCorredor = df_resultados[r, "terreno_costo_corredor"]
    costoDemolicion = df_resultados[r, "terreno_costo_demolicion"]
    otrosTerreno = df_resultados[r, "terreno_otros"]
    costoTotalTerreno = df_resultados[r, "terreno_costo_total"]
    costoUnitTerrenoTotal = df_resultados[r, "terreno_costo_unit_total"]
    dualMaxOcupación = df_resultados[r, "holgura_ocupacion"]
    dualMaxConstructibilidad = df_resultados[r, "holgura_constructibilidad"]
    dualMaxDensidad = df_resultados[r, "holgura_densidad"]
    ingresosVentas = df_resultados[r, "indicador_ingresos_ventas"]
    costoTotal = df_resultados[r, "indicador_costo_total"]
    margenAntesImpuesto = df_resultados[r, "indicador_margen_antes_impuesto"]
    impuestoRenta = df_resultados[r, "indicador_impuesto_renta"]
    utilidadDespuesImpuesto = df_resultados[r, "indicador_utilidad_despues_impuesto"]
    rentabilidadTotalBruta = df_resultados[r, "indicador_rentabilidad_total_bruta"]
    rentabilidadTotalNeta = df_resultados[r, "indicador_rentabilidad_total_neta"]
    incidenciaTerreno = df_resultados[r, "indicador_incidencia_terreno"]
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

    filestr = "C:\\Users\\rjvia\\.julia\\dev\\qgis_env\\aux_files\\imagenes_cabidas\\____cabida_vitacura_" * string(r) * ".png"
    
    fig, ax, ax_mat = polyShape.plotBaseEdificio3D(fpe, xopt, alturaPiso, ps_predio, ps_volTeorico, matConexionVertices_volTeorico, vecVertices_volTeorico, 
                                            ps_volConSombra, matConexionVertices_conSombra, vecVertices_conSombra, ps_publico, ps_calles, ps_base, ps_baseSeparada);

    buffer_dist_ = min(140, 2.7474774194546216 * xopt[1] * alturaPiso)

    ps_buffer_predio_ = polyShape.shapeBuffer(ps_predio, buffer_dist_, 20)
    ps_predios_intra_buffer_ = polyShape.polyIntersect(ps_predios_intra_buffer, ps_buffer_predio_)
    ps_manzanas_intra_buffer_ = polyShape.polyIntersect(ps_manzanas_intra_buffer, ps_buffer_predio_)

    fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_predios_intra_buffer_, 0.0, "green", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
    fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_manzanas_intra_buffer_, 0.0, "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
    fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_buffer_predio_, 0.0, "gray", 0.15, fig=fig, ax=ax, ax_mat=ax_mat, filestr=filestr)

    close("all")

    aux_str = "C:/Users/rjvial/.julia/dev/qgis_env/aux_files/imagenes_cabidas/cabida_vitacura_" * string(r) * ".png"
    executeStr = "UPDATE tabla_resultados_cabidas SET dir_image_file = \'" * aux_str * "\' WHERE combi_predios = \'" * df_resultados[r, "combi_predios"] * "\'"
    pg_julia.query(conn_LandValue, executeStr)


end

