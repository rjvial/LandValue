using LandValue, NonconvexBayesian, NonconvexIpopt, NonconvexNLopt, Distributions

codigo_predial = [151600124100009, 151600124100010, 151600124100011, 151600124100012, 151600124100013, 151600124100014, 151600124100015]

##############################################
# PARTE "1": OBTENCIÓN DE PARÁMETROS         #
##############################################

conn_LandValue = pg_julia.connection("LandValue", "postgres", "postgres")
conn_mygis_db = pg_julia.connection("mygis_db", "postgres", "postgres")


display("Obtiene DatosCabidaArquitectura")
@time df_arquitectura = pg_julia.query(conn_LandValue, """SELECT * FROM public."tabla_arquitectura_default";""")
dca = DatosCabidaArquitectura()
for field_s in fieldnames(DatosCabidaArquitectura)
    value_ = df_arquitectura[:, field_s][1]
    setproperty!(dca, field_s, value_)
end

display("Obtiene DatosCabidaUnit")
@time df_costosunitarios = pg_julia.query(conn_LandValue, """SELECT * FROM public."tabla_costosunitarios_default";""")
dcu = DatosCabidaUnit()
for field_s in fieldnames(DatosCabidaUnit)
    value_ = df_costosunitarios[:, field_s][1]
    setproperty!(dcu, field_s, value_)
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
superficieTerreno = sup_terreno_sii[1]
superficieTerrenoCalc = polyShape.polyArea(ps_predio)
dcp = DatosCabidaPredio(V_predio[:, 1], V_predio[:, 2], [], [], 0, 200)
numLotes = length(codigo_predial)
dcp.fusionTerrenos = numLotes >= 2 ? 1 : 0

#################################
# Obtiene predios y calles contenidos en el buffer del predio y ajusta coordenadas


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

display("Obtención del conjunto de calles en el entorno del predio")
@time ps_calles, ps_publico, ps_bruto, vecAnchoCalle, vecSecConCalle = obtieneCalles(ps_predio, ps_buffer_predio, ps_predios_buffer, ps_manzanas_buffer)
dcp.ladosConCalle = vecSecConCalle
dcp.anchoEspacioPublico = vecAnchoCalle

display("")
display("Inicio de Optimización Volumétrica: Predio N° " * string(codigo_predial))

display("Obtención de calles dentro del buffer")
@time ps_calles_intra_buffer = polyShape.polyIntersect(ps_calles, ps_buffer_predio)

# Obtiene ejes de calles contenidos al interior del buffer
display("Obtiene ejes de calles contenidos al interior del buffer")
@time ls_calles = queryCabida.query_calles_intra_buffer(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)

display("Calcula el espacio publico y bruto")
superficieTerrenoBrutaCalc = polyShape.polyArea(ps_bruto)
superficieTerrenoBruta = superficieTerrenoBrutaCalc / superficieTerrenoCalc * superficieTerreno


# Calcula matriz V_areaEdif asociada a los vértices del area de edificación
display("Establece el área de edificación")
V_areaEdif = copy(V_predio)
numLadosPredio = size(V_areaEdif, 1)
conjuntoLados = 1:numLadosPredio
conjuntoLadosCalle = dcp.ladosConCalle
conjuntoLadosVecinos = setdiff(conjuntoLados, conjuntoLadosCalle)
sepVecinos = dcn.distanciamiento
rasante = dcn.rasante
antejardin = dcn.antejardin
vecDist = fill(1.0, numLadosPredio)
vecDist[conjuntoLadosCalle] .= -antejardin[1]
vecDist[conjuntoLadosVecinos] .= -sepVecinos[1]
ps_areaEdif = PolyShape([V_predio], 1)
ps_areaEdif = polyShape.polyExpandSegmentVec(ps_areaEdif, vecDist, collect(conjuntoLados))
ps_areaEdif = polyShape.polySimplify(polyShape.polySimplify(ps_areaEdif))
V_areaEdif = ps_areaEdif.Vertices[1]
sup_areaEdif = polyShape.polyArea(ps_areaEdif)


# Calcula el volumen y sombra teórica 
display("Calcula el volumen teórico")
@time matConexionVertices_volTeorico, vecVertices_volTeorico, ps_volTeorico = generaVol3D(ps_predio, ps_bruto, rasante, dcn, dcp)
V_volTeorico = ps_volTeorico.Vertices[1]
vecAlturas_volTeorico = sort(unique(V_volTeorico[:, end]))

display("Calcula sombra del Volumen Teórico")
@time ps_sombraVolTeorico_p, ps_sombraVolTeorico_o, ps_sombraVolTeorico_s = generaSombraTeor(ps_volTeorico, matConexionVertices_volTeorico, vecVertices_volTeorico, ps_publico, ps_calles)
rasante_sombra = Float64(dcn.rasanteSombra)

display("Calcula el volumen sin restricciones")
@time matConexionVertices_conSombra, vecVertices_conSombra, ps_volConSombra = generaVol3D(ps_predio, ps_bruto, rasante_sombra, dcn, dcp)
V_volConSombra = ps_volConSombra.Vertices[1]
vecAlturas_conSombra = sort(unique(V_volConSombra[:, end]))

areaSombra_p = polyShape.polyArea(ps_sombraVolTeorico_p)
areaSombra_o = polyShape.polyArea(ps_sombraVolTeorico_o)
areaSombra_s = polyShape.polyArea(ps_sombraVolTeorico_s)


sepNaves = dca.anchoMin

maxSupConstruida = superficieTerreno * dcn.coefConstructibilidad * (1 + 0.3 * dcp.fusionTerrenos)
maxOcupación = dcn.coefOcupacion * superficieTerreno
flag_penalizacion_residual = true
flag_penalizacion_coefOcup = true
flag_penalizacion_constructibilidad = true
flag_conSombra = true
num_penalizaciones = flag_penalizacion_residual + flag_penalizacion_coefOcup + flag_penalizacion_constructibilidad + flag_conSombra


min_pisos_bbo = min(4, dcn.maxPisos[1] - 1)
alt_bbo = min_pisos_bbo * dca.alturaPiso

porcTerraza = 0.15/1.075
obj_nomad = x -> fo_nomad(x, template, sepNaves, dca, porcTerraza, flag_conSombra, flag_penalizacion_residual, flag_penalizacion_coefOcup, flag_penalizacion_constructibilidad,
V_volConSombra, vecAlturas_conSombra, vecVertices_conSombra, matConexionVertices_conSombra, 
V_volTeorico, vecAlturas_volTeorico, vecVertices_volTeorico, matConexionVertices_volTeorico,
maxOcupación, maxSupConstruida, areaSombra_p, areaSombra_o, areaSombra_s, ps_publico, ps_calles)


largos, angulosExt, angulosInt, largosDiag = polyShape.extraeInfoPoly(ps_areaEdif)
maxDiagonal = maximum(largosDiag)

default_min_pisos = 3

fopt = 10000.
flagSeguir = true
template = 0 # [0:I, 1:L, 2:C, 3:lll, 4:V, 5:H]
intento = 1
maxIntentos = 1

lb, ub = generaCotas(template, default_min_pisos, floor(dcn.maxPisos[1]), V_areaEdif, sepNaves, maxDiagonal, dca.anchoMin, dca.anchoMax)


function f(x)

    theta = x[2]
    pos_x = x[3]
    pos_y = x[4]
    anchoLado = x[5]
    largo = x[6]

    ps_base = polyShape.polyBox(pos_x, pos_y, anchoLado, largo, theta) 
        
    
    areaBasal = polyShape.polyArea(ps_base)

    #areaBasal = anchoLado * largo

    return -areaBasal
end


g(x::AbstractVector) = -x[1]

m = NonconvexBayesian.Model()

set_objective!(m, x -> f(x))
addvar!(m, lb, ub)

add_ineq_constraint!(m, x -> g(x))

alg = BayesOptAlg(IpoptAlg())
options = BayesOptOptions(
    sub_options=IpoptOptions(print_level=0), maxiter=10, ctol=1e-4,
    ninit=2, initialize=true, postoptimize=false, fit_prior=true,
)
r = optimize(m, alg, lb, options=options);
fopt = -r.minimum
xopt = r.minimizer
