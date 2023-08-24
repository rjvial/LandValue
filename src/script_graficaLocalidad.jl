
using LandValue, Distributed, DotEnv, BlackBoxOptim, Images, ImageBinarization

DotEnv.load("secrets.env")
datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
datos_mygis_db = ["gis_data", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
# datos_LandValue = ["landengines_local", "postgres", "", "localhost"]
# datos_mygis_db = ["gis_data_local", "postgres", "", "localhost"]

conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
conn_mygis_db = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])


let
    codigo_predial = [151600140700001, 151600140700002, 151600140700003, 151600140700005, 151600140700006, 151600140700007, 151600140700008, 151600140700009, 151600140700010, 151600140700004, 151600140700011, 151600140700012]  # id = 65


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

    filestr = "C:\\Users\\rjvia\\Documents\\Land_engines_code\\Julia\\localidad_65\\____localidad_65" * ".png"


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

    fig, ax, ax_mat = plotBaseEdificio3D(fpe, xopt, alturaPiso, ps_predio, ps_volTeorico, matConexionVertices_volTeorico, vecVertices_volTeorico,
        ps_volConSombra, matConexionVertices_conSombra, vecVertices_conSombra, ps_publico, ps_calles, ps_base, ps_baseSeparada)

    fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_predios_intra_buffer, 0.0, "green", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
    fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_manzanas_intra_buffer, 0.0, "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
    fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_buffer_predio, 0.0, "gray", 0.15, fig=fig, ax=ax, ax_mat=ax_mat, filestr=filestr)


    infileStr = "C:\\Users\\rjvia\\Documents\\Land_engines_code\\Julia\\localidad_65\\____localidad_65" * ".png"
    outfileStr = "C:\\Users\\rjvia\\Documents\\Land_engines_code\\Julia\\localidad_65\\localidad_65" * ".png"

    polyShape.imageWhiteSpaceReduction(infileStr, outfileStr)
end