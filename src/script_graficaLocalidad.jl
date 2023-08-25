
using LandValue, Distributed, DotEnv, BlackBoxOptim, Images, ImageBinarization

DotEnv.load("secrets.env")
datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
datos_mygis_db = ["gis_data", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
# datos_LandValue = ["landengines_local", "postgres", "", "localhost"]
# datos_mygis_db = ["gis_data_local", "postgres", "", "localhost"]

conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
conn_mygis_db = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])

localidad = 65
query_unique_lotes = """
SELECT unique_lotes FROM combi_locations
WHERE id_combi_list = $localidad
"""
df_unique_lotes = pg_julia.query(conn_LandValue, query_unique_lotes)
codigo_predial = eval.(Meta.parse.(replace(df_unique_lotes[1,"unique_lotes"], ";" => ",")))

display("Obtiene DatosCabidaArquitectura")
@time df_arquitectura = pg_julia.query(conn_LandValue, """SELECT * FROM public."tabla_arquitectura_default";""")
dca = DatosCabidaArquitectura()
for field_s in fieldnames(DatosCabidaArquitectura)
    value_ = df_arquitectura[:, field_s][1]
    setproperty!(dca, field_s, value_)
end

display("Obtiene FlagPlotEdif3D")
@time df_flagplot = pg_julia.query(conn_LandValue, """SELECT * FROM public."tabla_flagplot_default";""")
fpe = FlagPlotEdif3D()
for field_s in fieldnames(FlagPlotEdif3D)
    value_ = df_flagplot[:, field_s][1]
    setproperty!(fpe, field_s, value_)
end

codPredialStr = replace(replace(string(codigo_predial), "[" => "("), "]" => ")")

# Obtiene desde la base de datos los parametros del predio 
display("Obtiene desde la base de datos los parametros del predio")
@time dcn, sup_terreno_sii, ps_predio_db = queryCabida.query_datos_predio(conn_mygis_db, "vitacura", codPredialStr)

dcn.rasanteSombra = 5.0
dcn.flagDensidadBruta = true
dcn.estacionamientosPorViv = 1.0
dcn.porcAdicEstacVisitas = 0.15
dcn.supPorEstacionamiento = 30.0
dcn.supPorBodega = 5.0
dcn.estBicicletaPorEst = 0.5
dcn.bicicletasPorEst = 3.0
dcn.flagCambioEstPorBicicleta = true
dcn.maxSubte = 7.0
dcn.coefOcupacionEst = 0.8
dcn.sepEstMin = 7.0
dcn.reduccionEstPorDistMetro = false

# Simplifica, corrige orientacion y escala del predio
ps_predio_db = polyShape.setPolyOrientation(ps_predio_db, 1)
ps_predio_db, dx, dy = polyShape.ajustaCoordenadas(ps_predio_db)
ps_predio_db = polyShape.polyUnion(ps_predio_db)
simplify_value = 1.0 #1. #.1
ps_predio = polyShape.shapeSimplify(ps_predio_db, simplify_value)
ps_predio = polyShape.polyEliminaColineales(ps_predio)
V_predio = ps_predio.Vertices[1]
dcp = DatosCabidaPredio(V_predio[:, 1], V_predio[:, 2], [], [], 0, 200)
numLotes = length(codigo_predial)
dcp.fusionTerrenos = numLotes >= 2 ? 1 : 0

buffer_dist = 140

# Obtiene buffer del predio seleccionado
display("Obtiene buffer del predio seleccionado")
@time ps_buffer_predio = queryCabida.query_buffer_predio(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)


# Obtiene predios contenidos en el buffer del predio y ajusta coordenadas
display("Obtiene predios contenidos en el buffer del predio y ajusta coordenadas")
@time ps_predios_buffer = queryCabida.query_predios_buffer(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)

# Obtiene manzanas contenidas en el buffer del predio
display("Obtiene manzanas contenidas en el buffer del predio")
@time ps_manzanas_buffer = queryCabida.query_manzanas_buffer(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)

# display("Obtención del conjunto de calles en el entorno del predio")
@time ps_calles, ps_publico, ps_bruto, vecAnchoCalle, vecSecConCalle = obtieneCalles(ps_predio, ps_buffer_predio, ps_predios_buffer, ps_manzanas_buffer)

display("Obtención de calles dentro del buffer")
@time ps_calles_intra_buffer = polyShape.polyIntersect(ps_calles, ps_buffer_predio)

# Obtiene ejes de calles contenidos al interior del buffer
display("Obtiene ejes de calles contenidos al interior del buffer")
@time ls_calles = queryCabida.query_calles_intra_buffer(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)


# Obtiene calles al interior del buffer
ps_calles_intra_buffer = polyShape.polyIntersect(ps_calles, ps_buffer_predio)

# Obtiene predios contenidos al interior del buffer 
ps_predios_intra_buffer = queryCabida.query_predios_intra_buffer(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)

# Obtiene manzanas contenidas al interior del buffer 
ps_manzanas_intra_buffer = queryCabida.query_manzanas_intra_buffer(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)


buffer_dist_ = min(buffer_dist, 2.7474774194546216 * dcn.maxPisos[1] * dca.alturaPiso[1])
ps_buffer_predio = polyShape.shapeBuffer(ps_predio, buffer_dist_, 20)
ps_calles_intra_buffer = polyShape.shapeBuffer(ps_calles_intra_buffer, buffer_dist_, 20)
ps_predios_intra_buffer = polyShape.polyIntersect(ps_predios_intra_buffer, ps_buffer_predio)
ps_manzanas_intra_buffer = polyShape.polyIntersect(ps_manzanas_intra_buffer, ps_buffer_predio)

alturaPiso = dca.alturaPiso[1]

ps_volTeorico = []
matConexionVertices_volTeorico = []
vecVertices_volTeorico = []
ps_volConSombra = []
matConexionVertices_conSombra = []
vecVertices_conSombra = []
ps_base = []
ps_baseSeparada = []
ps_areaEdif = []
xopt = []

fpe.predio = true
fpe.volTeorico = false
fpe.volConSombra = false
fpe.edif = false
fpe.sombraVolTeorico_p = false
fpe.sombraVolTeorico_o = false
fpe.sombraVolTeorico_s = false
fpe.sombraEdif_p = false
fpe.sombraEdif_o = false
fpe.sombraEdif_s = false

dirStr = "C:\\Users\\rjvia\\Documents\\Land_engines_code\\Julia\\localidad_$localidad"
mkdir(dirStr)
infileStr = dirStr * "\\____localidad_$localidad" * ".png"
outfileStr = dirStr * "\\localidad_$localidad" * ".png"


fig, ax, ax_mat = plotBaseEdificio3D(fpe, xopt, alturaPiso, ps_predio, ps_volTeorico, matConexionVertices_volTeorico, vecVertices_volTeorico,
    ps_volConSombra, matConexionVertices_conSombra, vecVertices_conSombra, ps_publico, ps_calles, ps_base, ps_baseSeparada)

fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_predios_intra_buffer, 0.0, "green", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_manzanas_intra_buffer, 0.0, "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_buffer_predio, 0.0, "gray", 0.15, fig=fig, ax=ax, ax_mat=ax_mat, filestr=infileStr)

polyShape.imageWhiteSpaceReduction(infileStr, outfileStr)



query_resultados_str = """
SELECT id
FROM public.tabla_resultados_cabidas
WHERE id_combi_list = $localidad
"""
df_resultados = pg_julia.query(conn_LandValue, query_resultados_str)

numRows, numCols = size(df_resultados)
rowSet = sort(df_resultados[:,"id"])

let 

    for r in rowSet

        display("Generando Imagen de Cabida N° = " * string(r))
        display("")
    
        query_resultados_r = """
        SELECT combi_predios, optimo_solucion, ps_predio, ps_vol_teorico, mat_conexion_vertices_vol_teorico,
        "vecVertices_volTeorico", "ps_volConSombra", mat_conexion_vertices_con_sombra, vec_vertices_con_sombra, ps_base, 
        "ps_baseSeparada", dx, dy, id
        FROM public.tabla_resultados_cabidas
        WHERE id = $r
        """
        df_resultados_r = pg_julia.query(conn_LandValue, query_resultados_r)

        dx_r = df_resultados_r[:,"dx"][1]
        dy_r = df_resultados_r[:,"dy"][1]
        delta_x = dx - dx_r  
        delta_y = dy - dy_r

        codigo_predial = eval(Meta.parse(df_resultados_r[1, "combi_predios"]))
        xopt = eval(Meta.parse(df_resultados_r[1, "optimo_solucion"]))
        ps_predio_r = eval(Meta.parse(df_resultados_r[1, "ps_predio"]))
        ps_predio_r = polyShape.ajustaCoordenadas(ps_predio_r, delta_x, delta_y)
        ps_volTeorico = eval(Meta.parse(df_resultados_r[1, "ps_vol_teorico"]))
        ps_volTeorico = polyShape.ajustaCoordenadas(ps_volTeorico, delta_x, delta_y)
        matConexionVertices_volTeorico = eval(Meta.parse(df_resultados_r[1, "mat_conexion_vertices_vol_teorico"])) 
        vecVertices_volTeorico = eval(Meta.parse(df_resultados_r[1, "vecVertices_volTeorico"]))
        ps_volConSombra = eval(Meta.parse(df_resultados_r[1, "ps_volConSombra"]))
        ps_volConSombra = polyShape.ajustaCoordenadas(ps_volConSombra, delta_x, delta_y)
        matConexionVertices_conSombra = eval(Meta.parse(df_resultados_r[1, "mat_conexion_vertices_con_sombra"]))
        vecVertices_conSombra = eval(Meta.parse(df_resultados_r[1, "vec_vertices_con_sombra"]))
        ps_base = eval(Meta.parse(df_resultados_r[1, "ps_base"]))
        ps_base = polyShape.ajustaCoordenadas(ps_base, delta_x, delta_y)
        ps_baseSeparada = eval(Meta.parse(df_resultados_r[1, "ps_baseSeparada"]))
        ps_baseSeparada = polyShape.ajustaCoordenadas(ps_baseSeparada, delta_x, delta_y)
        id = df_resultados_r[1, "id"]
    
        infileStr = dirStr * "\\____cabida_vitacura_" * string(id) * ".png"
        outfileStr = dirStr * "\\cabida_vitacura_" * string(id) * ".png"
    
        fpe.predio = true
        fpe.volTeorico = true
        fpe.volConSombra = true
        fpe.edif = true
        fpe.sombraVolTeorico_p = true
        fpe.sombraVolTeorico_o = true
        fpe.sombraVolTeorico_s = true
        fpe.sombraEdif_p = true
        fpe.sombraEdif_o = true
        fpe.sombraEdif_s = true

        fig, ax, ax_mat = polyShape.plotBaseEdificio3D(fpe, xopt, alturaPiso, ps_predio, ps_volTeorico, matConexionVertices_volTeorico, vecVertices_volTeorico, 
                                                ps_volConSombra, matConexionVertices_conSombra, vecVertices_conSombra, ps_publico, ps_calles, ps_base, ps_baseSeparada);
    
    
        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_predio_r, 0.0, "blue", 0.01, fig=fig, ax=ax, ax_mat=ax_mat, line_width=0.5)
        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_predios_intra_buffer, 0.0, "green", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_manzanas_intra_buffer, 0.0, "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_buffer_predio, 0.0, "gray", 0.15, fig=fig, ax=ax, ax_mat=ax_mat, filestr=infileStr)


        close("all")
    
        infileStr = "C:\\Users\\rjvia\\Documents\\Land_engines_code\\Julia\\localidad_$localidad\\____cabida_vitacura_" * string(r) * ".png"
        outfileStr = "C:\\Users\\rjvia\\Documents\\Land_engines_code\\Julia\\localidad_$localidad\\cabida_vitacura_" * string(r) * ".png"
    
        polyShape.imageWhiteSpaceReduction(infileStr, outfileStr)
    
    
    end
    
    
end
