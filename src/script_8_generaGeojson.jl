using LandValue, DotEnv

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

# display("Obtiene listado de todas las combinaciones")
# query_resultados_str = """
# select id from tabla_resultados_cabidas ORDER BY id ASC;
# """
# df_id = pg_julia.query(conn_LandValue, query_resultados_str)

# numRows, numCols = size(df_id)
# rowSet = df_id[:,"id"]

display("Obtiene listado de las combinaciones que con max gap para cada localidad")
query_max_gap = """
    SELECT id_combi_list, MAX(gap) AS max_gap, 
    (SELECT id AS id_max_gap FROM tabla_resultados_cabidas t2 WHERE t2.id_combi_list = t1.id_combi_list AND t2.gap = MAX(t1.gap))
    FROM tabla_resultados_cabidas t1
    GROUP BY id_combi_list
    ORDER BY id_combi_list
"""
df_max_gap = pg_julia.query(conn_LandValue, query_max_gap)
rowSet = df_max_gap[:, "id_max_gap"]



for r in rowSet
    display("Generando Archivo GeoJson de Cabida N° = " * string(r))
    display("")

    r_str = string(r)
    query_resultados_r = """
    select * from tabla_resultados_cabidas where id = $r_str ORDER BY id ASC;
    """
    df_r = pg_julia.query(conn_LandValue, query_resultados_r)


    codigo_predial = eval(Meta.parse(df_r[1, "combi_predios"]))
    temp_opt = df_r[1, "cabida_temp_opt"]
    numPisos = df_r[1, "cabida_num_pisos"]
    altura = df_r[1, "cabida_altura"]
    xopt = eval(Meta.parse(df_r[1, "optimo_solucion"]))
    ps_predio = eval(Meta.parse(df_r[1, "ps_predio"]))
    ps_volTeorico = eval(Meta.parse(df_r[1, "ps_vol_teorico"]))
    matConexionVertices_volTeorico = eval(Meta.parse(df_r[1, "mat_conexion_vertices_vol_teorico"])) 
    vecVertices_volTeorico = eval(Meta.parse(df_r[1, "vecVertices_volTeorico"]))
    ps_volConSombra = eval(Meta.parse(df_r[1, "ps_volConSombra"]))
    matConexionVertices_conSombra = eval(Meta.parse(df_r[1, "mat_conexion_vertices_con_sombra"]))
    vecVertices_conSombra = eval(Meta.parse(df_r[1, "vec_vertices_con_sombra"]))
    ps_publico = eval(Meta.parse(df_r[1, "ps_publico"]))
    ps_calles = eval(Meta.parse(df_r[1, "ps_calles"]))
    ps_base = eval(Meta.parse(df_r[1, "ps_base"]))
    ps_baseSeparada = eval(Meta.parse(df_r[1, "ps_baseSeparada"]))
    ps_predios_intra_buffer = eval(Meta.parse(df_r[1, "ps_predios_intra_buffer"]))
    ps_manzanas_intra_buffer = eval(Meta.parse(df_r[1, "ps_manzanas_intra_buffer"]))
    ps_calles_intra_buffer = eval(Meta.parse(df_r[1, "ps_calles_intra_buffer"]))
    V_aux = copy(ps_volTeorico.Vertices[1][ps_volTeorico.Vertices[1][:,3] .== 0, 1:2])
    ps_areaEdif = PolyShape([V_aux], 1)
    dx = df_r[1, "dx"]
    dy = df_r[1, "dy"]
    id = df_r[1, "id"]
    id_combi = df_r[1, "id_combi_list"]
    valor_mercado_combi = df_r[1, "valor_mercado_combi"]
    gap = df_r[1, "gap"]
    gap_porcentual = df_r[1, "gap_porcentual"]
    
    filestr = "C:/Users/rjvia/Documents/Land_engines_code/Julia/edificios_geojson/edificio_" * string(id) * "_vitacura.geojson"
    # filestr = "C:/Users/rjvia/Documents/Land_engines_code/Julia/edificios_geojson_todos/edificio_" * string(id) * "_vitacura.geojson"

    create_edificio_geojson(xopt, ps_predio, ps_base, ps_areaEdif, alturaPiso, dx, dy, filestr, gap_porcentual)

end

