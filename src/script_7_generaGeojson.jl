using LandValue

conn_LandValue = pg_julia.connection("LandValue", "postgres", "postgres")
conn = conn_LandValue 
# conn_CitylotsVitacura = pg_julia.connection("citylots_vitacura", "citylots_rvg", "******", "az1-ts102.a2hosting.com")
# conn = conn_CitylotsVitacura 

display("Obtiene DatosCabidaArquitectura")
@time df_arquitectura = pg_julia.query(conn_LandValue, """SELECT * FROM public."tabla_arquitectura_default";""")
dca = DatosCabidaArquitectura()
for field_s in fieldnames(DatosCabidaArquitectura)
    value_ = df_arquitectura[:, field_s][1]
    setproperty!(dca, field_s, value_)
end
alturaPiso = dca.alturaPiso

query_resultados_str = """
select * from tabla_resultados_cabidas ORDER BY id ASC;
"""
df_resultados = pg_julia.query(conn, query_resultados_str)

numRows, numCols = size(df_resultados)
rowSet = 1:numRows


for r in rowSet
    display("Generando Archivo GeoJson de Cabida N° = " * string(r))
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
    V_aux = copy(ps_volTeorico.Vertices[1][ps_volTeorico.Vertices[1][:,3] .== 0, 1:2])
    ps_areaEdif = PolyShape([V_aux], 1)
    dx = df_resultados[r, "dx"]
    dy = df_resultados[r, "dy"]
    id = df_resultados[r, "id"]
    
    filestr = "C:/Users/rjvia/.julia/dev/qgis_env/cabidas_geojson/edificio_" * string(id) * "_vitacura.geojson"

    create_edificio_geojson(xopt, ps_predio, ps_base, ps_areaEdif, alturaPiso, dx, dy, filestr)

end

