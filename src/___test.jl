
using LandValue, DotEnv, LinearAlgebra, OrderedCollections, JSON


my_env = DotEnv.config("secrets.env")
conn_aws = aws_julia.connection(my_env["AWS_ACCESS_KEY"], my_env["AWS_SECRET_KEY"], my_env["AWS_REGION"])

neo4j_host = "bolt://localhost:7687"
# neo4j_host = "bolt://localhost:7688"
neo4j_user = "neo4j"
neo4j_password = "x67y1332"
key_pair = "neo4j-key-pair.pem"
ec2_user = "ec2-user"
public_dns = aws_julia.find_instance_by_name("Neo4j-EC2", conn_aws)["dnsName"]
folder = "/usr/bin/cypher-shell"
conn_neo4j = neo4j_julia.connection(neo4j_host, neo4j_user, neo4j_password, folder, key_pair, ec2_user, public_dns)

pg_public_dns = aws_julia.find_instance_by_name("Postgres-EC2", conn_aws)["dnsName"]
conn_postgres = pg_julia.connection("landengines", my_env["PG_AWS_USER"], my_env["PG_AWS_PASSWORD"], pg_public_dns)


fpe = FlagPlotEdif3D()
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

################################################################################
#                          HELPER FUNCTIONS                                  #
################################################################################


function update_optimization_status(conn_postgres, id_opti, status)
    update_query = """
    UPDATE public.tabla_instancias_optimizacion
    SET status = $status
    WHERE id_opti = $id_opti
    """
    pg_julia.query(conn_postgres, update_query)
end

function handle_optimization_error(conn_postgres, id_opti, error_msg, error)
    println("$error_msg for ID $id_opti: $error")
    update_optimization_status(conn_postgres, id_opti, -1)
end

function juliaTypeToPgType(juliaType::Type)
    if juliaType <: Integer
        return "int4"
    elseif juliaType <: AbstractFloat
        return "numeric(10,2)"
    elseif juliaType <: AbstractString
        return "text"
    elseif juliaType <: Bool
        return "boolean"
    else
        return "text"
    end
end

function dict2tablevec(dict, primaryKeyStr::String="id")
    vecColumnNames = [string(k) for k in keys(dict)]
    if !(primaryKeyStr in vecColumnNames)
        push!(vecColumnNames, primaryKeyStr)
    end
    vecColumnTypes = [juliaTypeToPgType(typeof(haskey(dict, col) ? dict[col] : 1)) for col in vecColumnNames]
    return vecColumnNames, vecColumnTypes
end

function processValue(value, dict_geom)
    if typeof(value) == Bool
        return value ? 1 : 0
    elseif isa(value, Tuple)
        tuple_str = string(value)
        tuple_str = replace(tuple_str, r"[\"'\[\](){}]" => " ")
        return strip(tuple_str)
    else
        return value
    end
end

function createArchitectureDict(variante_norm)
    return OrderedDict(
        "arq_alturaPiso" => 2.55,
        "arq_K" => 1,
        "arq_ancho_crujia_min" => 8,
        "arq_ancho_crujia_max" => 18,
        "arq_tipo_edificio" => "departamento",
        "arq_flag_sombra" => true,
        "arq_flag_vano" => false,
        "arq_vecSupInterior" => [25, 65, 85, 120, 240],
        "arq_vecSupTerraza" => [10, 20, 30, 40, 40],
        "arq_vecSupUtil" => [30, 75, 100, 140, 260],
        "arq_supPorEstacionamiento" => 30,
        "arq_supPorBodega" => 5,
        "arq_supPorBicicleta" => 4,
        "arq_coefSupComunPisosSup" => 0.12,
        "arq_coefSupComun" => 0.18,
        "arq_variante_normativa" => variante_norm
    )
end

################################################################################
#                          DATA LOADING SECTION                              #
################################################################################

query_pg = """
SELECT * FROM public.tabla_instancias_optimizacion
WHERE status = 0
ORDER BY id_opti ASC
"""
df_instancias = pg_julia.query(conn_postgres, query_pg)

query_combis = """
MATCH (p:Predio)-[:CONFORMA_COMBI]->(c:Combi)
RETURN DISTINCT c.id_combi AS id_combi, c.predios AS list_predios
ORDER BY id_combi
"""
df_combis = neo4j_julia.cypher_to_dataframe(query_combis, conn_neo4j)

lista_combi_instancias = unique(df_instancias.id_combi)
cypher_list = "[" * join("\"" .* lista_combi_instancias .* "\"", ", ") * "]"

println("Loading geometries from Neo4j...")
query_geom = """
MATCH (c:Combi)-[:CONTIENE_CALLES]->(cc:Calle_Combi)
WHERE c.id_combi IN $cypher_list
RETURN DISTINCT c.id_combi AS id_combi, c.sup_combi_sii AS sup_terreno_sii,
        c.geom_combi AS geom_wkt, c.num_predios AS num_predios,
        c.calles_contexto_wkt AS calles_contexto_wkt,
        cc.id_calle_combi AS id_calle_combi, cc.geom_wkt AS calles_combi_wkt
ORDER BY id_combi, id_calle_combi
"""
df_combined = neo4j_julia.cypher_to_dataframe(query_geom, conn_neo4j)

println("Loading tipo deptos from athena...")
query = """
SELECT * FROM portal_tipo_deptos
WHERE comuna = 'vitacura'
"""
DB_NAME = "iceberg_db"
athena_bucket = "landengines-data"
athena_output = "query-results"
athena_catalog_name = "AwsDataCatalog"
df_tipo_deptos = aws_julia.query_to_dataframe(query, DB_NAME, athena_bucket, athena_output, athena_catalog_name, conn_aws)


const PRIMARY_KEY = "id_opti"
const TABLE_NAME = "tabla_resultados_optimizacion"
const PRIORITY_KEYS = ["id_opti", "id_combi", "flag_sombra", "arq_variante_normativa", "arq_tipo_edificio"]

flag_create_table = false # let flag_create_table = false

# Check if results table already exists
table_check_query = """
SELECT 1 FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = '$TABLE_NAME'
"""
existing_table = pg_julia.query(conn_postgres, table_check_query)
if isempty(existing_table)
    flag_create_table = true
    println("Table '$TABLE_NAME' does not exist, will create on first result")
else
    println("Table '$TABLE_NAME' already exists")
end

combi_aux = ""
dict_geom = nothing

row = df_instancias[4,:]

id_combi = row.id_combi
id_opti = row.id_opti

df_combis_row = filter(r -> r.id_combi == id_combi, df_combis)
vec_predios = parse.(Int, split(strip(df_combis_row[1, "list_predios"], ['(', ')']), ';'))

# Process geometry once per combi
if id_combi != combi_aux
    println("\nProcessing Combi ID: $id_combi\n")
    df_combined_row = filter(r -> r.id_combi == id_combi, df_combined)
    dict_geom = obtiene_geometrias_combi(df_combined_row)
    combi_aux = id_combi
end

println("Processing ID Opti: $(id_opti)")


dict_arquitectura = createArchitectureDict(row.variante_norm)
dict_normativa_raw, id_zona_edificacion = obtiene_requerimientos_normativos(vec_predios[1], dict_arquitectura["arq_variante_normativa"], conn_neo4j)

# id_zona_edificacion = "15160_e_aa1"
df_tipo_deptos_filtered = filter(r -> r.id_zona_edificacion == id_zona_edificacion, df_tipo_deptos)
dict_arquitectura["arq_vecSupUtil"] = Float64.(JSON.parse(df_tipo_deptos_filtered[1,"sup_util_tipos_comuna"]))
dict_arquitectura["arq_vecSupInterior"] = Float64.(JSON.parse(df_tipo_deptos_filtered[1,"sup_interior_tipos_comuna"]))
dict_arquitectura["arq_vecSupTerraza"] = Float64.(JSON.parse(df_tipo_deptos_filtered[1,"sup_terraza_tipos_comuna"]))
dict_arquitectura["arq_vecDormitorios"] = Float64.(JSON.parse(df_tipo_deptos_filtered[1,"n_dorm_tipos_comuna"]))
dict_arquitectura["arq_vecBanos"] = Float64.(JSON.parse(df_tipo_deptos_filtered[1,"n_banos_tipos_comuna"]))

dict_proyecto, dict_normativa = opti_edificio(dict_geom, dict_arquitectura, dict_normativa_raw, id_opti, id_combi)


##########
# TEST 1 #
##########

vec_sup_deptos = dict_arquitectura["arq_vecSupInterior"][dict_proyecto["proyecto_vec_num_deptos_primerPiso"].>=1]
vec_num_deptos = dict_proyecto["proyecto_vec_num_deptos_primerPiso"][dict_proyecto["proyecto_vec_num_deptos_primerPiso"].>=1]
vec_sup_terraza = dict_arquitectura["arq_vecSupTerraza"][dict_proyecto["proyecto_vec_num_deptos_primerPiso"].>=1]
ps_planta = dict_proyecto["proyecto_vec_ps_opt"][1]

results_1 = opti_floor_plan(ps_planta, vec_sup_deptos, vec_num_deptos,
            vec_sup_terraza=vec_sup_terraza,
            ancho_pasillo=1.5,
            min_largo_pasillo=5.0,
            pasillo_centrado=true,
            area_escala=20.0,
            min_ancho_escala=4.0,
            max_ancho_terraza=4.0,
            tipo_escala=:interior,
            layout=:ns,
            balance_mode=:heuristic)


##########
# TEST 2 #
##########
ancho_pasillo=1.5
min_largo_pasillo=5.0
pasillo_centrado=true
area_escala=20.0
min_ancho_escala=4.0
max_ancho_terraza=4.0
tipo_escala=:interior
layout=:ns
balance_mode=:heuristic
is_vertical = (layout == :oe)


tipo_escala in [:exterior, :interior, :none] || error("tipo_escala must be :exterior, :interior, or :none")

get_area(t::Tuple{Float64, Int}) = t[1]
get_tipo(t::Tuple{Float64, Int}) = t[2]

get_area(t::Tuple{Float64, Int, Int}) = t[1]
get_tipo(t::Tuple{Float64, Int, Int}) = t[2]
get_index(t::Tuple{Float64, Int, Int}) = t[3]

# ══════════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════════

# ──────────────────────────────────────────────────────────────────────────────────
# Geometry generation helpers
# ──────────────────────────────────────────────────────────────────────────────────

# Generates apartment geometries along one strip, adjusting dimensions iteratively to fit available space
function genera_deptos_franja(vec_orden_deptos::Vector{Tuple{Float64, Int}}, coord_min_planta::Float64, dimension_franja::Float64, dimension_disponible::Float64, min_ancho_escala::Float64, is_vertical::Bool, coord_base::Float64, franja::Symbol)
    vec_coord_ini = Float64[]
    vec_coord_fin = Float64[]
    vec_dimension1_deptos = Float64[]
    vec_dimension2_deptos = Float64[]
    vec_tipo_deptos = Int[]

    dimension_franja_adjusted = dimension_franja
    max_iterations = 10

    for _ in 1:max_iterations
        empty!(vec_coord_ini)
        empty!(vec_coord_fin)
        empty!(vec_dimension1_deptos)
        empty!(vec_dimension2_deptos)
        empty!(vec_tipo_deptos)

        coord_current = coord_min_planta
        total_dimension = 0.0

        for depto in vec_orden_deptos
            sup_depto = get_area(depto)
            tipo_depto = get_tipo(depto)
            if tipo_depto == -1
                dim2 = sup_depto / dimension_franja_adjusted
                if dim2 < min_ancho_escala
                    dim2 = min_ancho_escala
                    dim1 = sup_depto / dim2
                else
                    dim1 = dimension_franja_adjusted
                end
            else
                dim2 = sup_depto / dimension_franja_adjusted
                dim1 = dimension_franja_adjusted
            end

            push!(vec_coord_ini, coord_current)
            push!(vec_coord_fin, coord_current + dim2)
            push!(vec_dimension1_deptos, dim1)
            push!(vec_dimension2_deptos, dim2)
            push!(vec_tipo_deptos, tipo_depto)
            coord_current += dim2
            total_dimension += dim2
        end

        if abs(total_dimension - dimension_disponible) / dimension_disponible < 0.005
            break
        end

        dimension_franja_adjusted = dimension_franja_adjusted * (total_dimension / dimension_disponible)
    end

    vec_ps_deptos_normalizado = PolyShape[]
    for i in eachindex(vec_coord_ini)
        ps_depto = polyBoxAligned(coord_base, vec_coord_ini[i], vec_dimension1_deptos[i], vec_dimension2_deptos[i], franja, is_vertical)
        push!(vec_ps_deptos_normalizado, ps_depto)
    end

    return vec_coord_ini, vec_coord_fin, vec_dimension1_deptos, vec_dimension2_deptos, vec_tipo_deptos, vec_ps_deptos_normalizado
end

# Extends apartments with corridor space overlap, then subtracts corridor geometry
function extiende_deptos_con_interseccion_pasillo(vec_coord_ini::Vector{Float64}, vec_coord_fin::Vector{Float64}, vec_dimension1_deptos::Vector{Float64}, vec_dimension2_deptos::Vector{Float64}, coord_base::Float64, ps_pasillo::PolyShape, extend_franja::Symbol, is_vertical::Bool, vec_ps_deptos_normalizado::Vector{PolyShape}, ps_pasillo_normalizado::PolyShape)
    vec_extension_dimension1 = Float64[]
    ps_deptos_extendidos = PolyShape[]

    for i in eachindex(vec_coord_ini)
        ps_depto_normalizado = vec_ps_deptos_normalizado[i]
        ps_intersection = polyShape.polyIntersection(ps_depto_normalizado, ps_pasillo_normalizado)
        intersection_area = polyShape.polyArea(ps_intersection)

        if intersection_area > 0.0
            extension_dimension = intersection_area / vec_dimension2_deptos[i]
        else
            extension_dimension = 0.0
        end

        push!(vec_extension_dimension1, extension_dimension)

        dimension1_total = vec_dimension1_deptos[i] + extension_dimension
        dimension2 = vec_coord_fin[i] - vec_coord_ini[i]

        extended_local_poly = polyBoxAligned(coord_base, vec_coord_ini[i], dimension1_total, dimension2, extend_franja, is_vertical)
        extended_poly_final = polyShape.polyDifference(extended_local_poly, ps_pasillo)
        push!(ps_deptos_extendidos, extended_poly_final)
    end

    return ps_deptos_extendidos, vec_extension_dimension1
end

# Creates terrace geometries for each apartment based on required areas and available dimensions
function genera_terrazas_franja(vec_orden_deptos::Vector{Tuple{Float64, Int}}, vec_sup_terraza::Vector{Float64}, vec_dimension2_deptos::Vector{Float64}, vec_coord_ini::Vector{Float64}, coord_terrace_base::Vector{Float64}, terrace_franja::Symbol, max_ancho_terraza::Float64, is_vertical::Bool)
    vec_terrazas = PolyShape[]

    for (i, depto) in enumerate(vec_orden_deptos)
        tipo_depto = get_tipo(depto)
        if tipo_depto == -1
            push!(vec_terrazas, PolyShape([zeros(0, 2)], 0))
        else
            area_terraza = vec_sup_terraza[tipo_depto]
            if area_terraza > 0.0
                dimension2_depto = vec_dimension2_deptos[i]

                dim_parallel = min(dimension2_depto, area_terraza / 1.75)
                dim_perpendicular = area_terraza / dim_parallel

                if dim_perpendicular > max_ancho_terraza
                    dim_perpendicular = max_ancho_terraza
                end

                coord_depto_ini = vec_coord_ini[i]
                coord_terraza_ini = coord_depto_ini + (dimension2_depto - dim_parallel) / 2

                terrace_poly = polyBoxAligned(coord_terrace_base[i], coord_terraza_ini, dim_perpendicular, dim_parallel, terrace_franja, is_vertical)
                push!(vec_terrazas, terrace_poly)
            else
                push!(vec_terrazas, PolyShape([zeros(0, 2)], 0))
            end
        end
    end

    return vec_terrazas
end

# ──────────────────────────────────────────────────────────────────────────────────
# Geometric transformation helpers
# ──────────────────────────────────────────────────────────────────────────────────

# Rotates vector of polyshapes back to original orientation around center point
function rota_polyshapes(vec_polyshapes::Vector{PolyShape}, angulo_rotacion::Float64, cr::Vector{Float64})
    vec_polyshapes_rotados = PolyShape[]

    for polyshape in vec_polyshapes
        if polyShape.polyArea(polyshape) > 0.0
            polyshape_rotado = polyShape.polyRotate(polyshape, -angulo_rotacion, cr)
            push!(vec_polyshapes_rotados, polyshape_rotado)
        else
            push!(vec_polyshapes_rotados, polyshape)
        end
    end

    return vec_polyshapes_rotados
end

# Safely translates a polyshape, handling empty polyshapes
function safe_translate(ps::PolyShape, dx::Float64, dy::Float64)
    if isempty(ps.Vertices) || polyShape.polyArea(ps) == 0.0
        return ps
    else
        return polyShape.polyTranslate(ps, dx, dy)
    end
end

# Creates axis-aligned box with franja-aware positioning (vertical: X-axis, horizontal: Y-axis)
function polyBoxAligned(base1::Float64, base2::Float64, dim1::Float64, dim2::Float64, franja::Symbol, is_vertical::Bool)
    if is_vertical
        offset = (franja == :este) ? base1 : base1 - dim1
        return polyShape.polyBox(offset, base2, dim1, dim2, 0.0)
    else
        offset = (franja == :norte) ? base1 : base1 - dim1
        return polyShape.polyBox(base2, offset, dim2, dim1, 0.0)
    end
end

# ──────────────────────────────────────────────────────────────────────────────────
# Coordinate and bounds helpers
# ──────────────────────────────────────────────────────────────────────────────────

# Returns coordinate index for axis (1 for X, 2 for Y)
function get_coord_index(is_vertical::Bool)
    return is_vertical ? 1 : 2
end

# Returns floor plan min and max coordinates
function get_floor_bounds(vec_planta::Vector{Float64})
    return minimum(vec_planta), maximum(vec_planta)
end

# Returns min or max coordinate from non-empty terraces along axis
function get_terrace_bounds(vec_terrazas::Vector{PolyShape}, is_vertical::Bool, get_max::Bool)
    terrazas_con_area = [t for t in vec_terrazas if polyShape.polyArea(t) > 0.0]
    isempty(terrazas_con_area) && return nothing

    coord_idx = get_coord_index(is_vertical)
    return get_max ? maximum([maximum(t.Vertices[1][:, coord_idx]) for t in terrazas_con_area]) :
                        minimum([minimum(t.Vertices[1][:, coord_idx]) for t in terrazas_con_area])
end

# Returns outermost extent of apartments and terraces along axis
function get_strip_outermost_extent(vec_ps_deptos::Vector{PolyShape}, vec_terrazas::Vector{PolyShape}, is_vertical::Bool, get_max::Bool)
    coord_idx = get_coord_index(is_vertical)
    all_coords = Float64[]

    for apt in vec_ps_deptos
        if polyShape.polyArea(apt) > 0.0
            append!(all_coords, apt.Vertices[1][:, coord_idx])
        end
    end

    for terrace in vec_terrazas
        if polyShape.polyArea(terrace) > 0.0
            append!(all_coords, terrace.Vertices[1][:, coord_idx])
        end
    end

    isempty(all_coords) && return nothing
    return get_max ? maximum(all_coords) : minimum(all_coords)
end

# Translates all geometries by delta in specified franja
function apply_terrace_correction(vec_ps_deptos1::Vector{PolyShape}, vec_ps_deptos2::Vector{PolyShape},
                                    vec_terrazas1::Vector{PolyShape}, vec_terrazas2::Vector{PolyShape},
                                    ps_pasillo::PolyShape, delta::Float64, is_vertical::Bool, franja::Symbol)
    dx, dy = is_vertical ? ((franja == :este ? delta : -delta), 0.0) : (0.0, (franja == :norte ? delta : -delta))

    return ([safe_translate(p, dx, dy) for p in vec_ps_deptos1],
            [safe_translate(p, dx, dy) for p in vec_ps_deptos2],
            [safe_translate(t, dx, dy) for t in vec_terrazas1],
            [safe_translate(t, dx, dy) for t in vec_terrazas2],
            safe_translate(ps_pasillo, dx, dy))
end

# Corrects outbound terraces by shifting geometries; limits shift to prevent opposite side outbound
function correct_outbound_terraces(vec_terrazas1::Vector{PolyShape}, vec_terrazas2::Vector{PolyShape},
                                    vec_ps_deptos1::Vector{PolyShape}, vec_ps_deptos2::Vector{PolyShape},
                                    ps_pasillo::PolyShape, vec_floor_coords::Vector{Float64},
                                    is_vertical::Bool, franja1_outbound::Bool, get_max_outbound::Bool)

    outbound_terraces = franja1_outbound ? vec_terrazas1 : vec_terrazas2
    inbound_terraces = franja1_outbound ? vec_terrazas2 : vec_terrazas1
    inbound_deptos = franja1_outbound ? vec_ps_deptos2 : vec_ps_deptos1

    outbound_coord = get_terrace_bounds(outbound_terraces, is_vertical, get_max_outbound)
    outbound_coord === nothing && return vec_ps_deptos1, vec_ps_deptos2, vec_terrazas1, vec_terrazas2, ps_pasillo

    floor_min, floor_max = get_floor_bounds(vec_floor_coords)
    target_coord = get_max_outbound ? floor_max : floor_min
    delta = abs(outbound_coord - target_coord)

    inbound_outermost = get_strip_outermost_extent(inbound_deptos, inbound_terraces, is_vertical, !get_max_outbound)
    if inbound_outermost !== nothing
        inbound_limit = get_max_outbound ? floor_min : floor_max
        max_safe_delta = abs(inbound_outermost - inbound_limit)
        delta = min(delta, max_safe_delta)
    end

    if delta > 0.0
        shift_franja = get_max_outbound ? (is_vertical ? :oeste : :sur) : (is_vertical ? :este : :norte)
        vec_ps_deptos1, vec_ps_deptos2, vec_terrazas1, vec_terrazas2, ps_pasillo =
            apply_terrace_correction(vec_ps_deptos1, vec_ps_deptos2, vec_terrazas1, vec_terrazas2,
                                    ps_pasillo, delta, is_vertical, shift_franja)
    end

    return vec_ps_deptos1, vec_ps_deptos2, vec_terrazas1, vec_terrazas2, ps_pasillo
end

# ──────────────────────────────────────────────────────────────────────────────────
# Floor normalization and distribution helpers
# ──────────────────────────────────────────────────────────────────────────────────

# Rotates floor plan to axis-aligned rectangle with width > height, returns dimensions and transformation
function normaliza_planta_rectangular(ps_planta::PolyShape)
    V_planta = ps_planta.Vertices[1]
    x_cr = sum(V_planta[1:end-1, 1]) / (size(V_planta, 1) - 1)
    y_cr = sum(V_planta[1:end-1, 2]) / (size(V_planta, 1) - 1)
    cr = [x_cr, y_cr]

    edge1 = V_planta[2, :] - V_planta[1, :]
    angulo_rotacion = -atan(edge1[2], edge1[1])

    ps_planta_normalizado = polyShape.polyRotate(ps_planta, angulo_rotacion, cr)
    V_planta_normalizado = ps_planta_normalizado.Vertices[1]

    vec_x_planta = V_planta_normalizado[:, 1]
    vec_y_planta = V_planta_normalizado[:, 2]
    W = maximum(vec_x_planta) - minimum(vec_x_planta)
    H = maximum(vec_y_planta) - minimum(vec_y_planta)

    if H > W
        angulo_rotacion += π/2
        ps_planta_normalizado = polyShape.polyRotate(ps_planta, angulo_rotacion, cr)
        V_planta_normalizado = ps_planta_normalizado.Vertices[1]
        vec_x_planta = V_planta_normalizado[:, 1]
        vec_y_planta = V_planta_normalizado[:, 2]
        W, H = H, W
    end

    return W, H, vec_x_planta, vec_y_planta, angulo_rotacion, cr, ps_planta_normalizado
end

# Distributes apartments between two strips balancing total area, adds staircase to strip 2 if tipo_escala is :exterior
function distribuye_deptos_entre_franjas(vec_sup_deptos::Vector{Float64}, vec_num_deptos::Vector{Int}, area_escala::Float64, tipo_escala::Symbol)
    deptos_individuales = Tuple{Float64, Int, Int}[]
    for tipo_depto in 1:length(vec_sup_deptos)
        sup_depto = vec_sup_deptos[tipo_depto]
        for j in 1:vec_num_deptos[tipo_depto]
            push!(deptos_individuales, (sup_depto, tipo_depto, j))
        end
    end

    sort!(deptos_individuales, by = x -> x[1], rev = true)

    deptos_franja1 = Tuple{Float64, Int, Int}[]
    deptos_franja2 = Tuple{Float64, Int, Int}[]
    area_franja1 = 0.0
    area_franja2 = 0.0

    escala_offset = (tipo_escala == :exterior) ? area_escala : 0.0

    for depto in deptos_individuales
        sup_depto = get_area(depto)
        if area_franja1 <= area_franja2 + escala_offset
            push!(deptos_franja1, depto)
            area_franja1 += sup_depto
        else
            push!(deptos_franja2, depto)
            area_franja2 += sup_depto
        end
    end

    if tipo_escala == :exterior
        push!(deptos_franja2, (area_escala, -1, 1))
        area_franja2 += area_escala
    end

    return deptos_franja1, deptos_franja2, area_franja1, area_franja2
end

# Calculates strip widths from areas and floor dimensions, scales if exceeding available space
function calcula_dimensiones_franjas(area_franja1::Float64, area_franja2::Float64, W::Float64, H::Float64, ancho_pasillo::Float64, dimension_terraza_max::Float64, is_vertical::Bool)
    if is_vertical
        dimension_disponible_franja = W - 2 * dimension_terraza_max - ancho_pasillo
        dimension_franja1_requerida = area_franja1 / H
        dimension_franja2_requerida = area_franja2 / H
    else
        dimension_disponible_franja = H - 2 * dimension_terraza_max - ancho_pasillo
        dimension_franja1_requerida = area_franja1 / W
        dimension_franja2_requerida = area_franja2 / W
    end

    if dimension_franja1_requerida + dimension_franja2_requerida > dimension_disponible_franja
        scale_factor = dimension_disponible_franja / (dimension_franja1_requerida + dimension_franja2_requerida)
        dimension_franja1 = dimension_franja1_requerida * scale_factor
        dimension_franja2 = dimension_franja2_requerida * scale_factor
    else
        dimension_franja1 = dimension_franja1_requerida
        dimension_franja2 = dimension_franja2_requerida
    end

    return dimension_franja1, dimension_franja2
end

# Orders apartments within each strip, placing staircase centrally if present and balancing layout
function ordena_deptos_en_franja(deptos_franja1::Vector{Tuple{Float64, Int, Int}}, deptos_franja2::Vector{Tuple{Float64, Int, Int}}, deptos_total::Int, tipo_escala::Symbol; balance_mode::Symbol = :heuristic)
    deptos_ordenados1 = Tuple{Float64, Int}[]
    deptos_ordenados2 = Tuple{Float64, Int}[]

    num_deptos1 = length(deptos_franja1)
    num_deptos2 = (tipo_escala == :exterior) ? length(deptos_franja2) - 1 : length(deptos_franja2)

    area_escala = (tipo_escala == :exterior) ? get_area(deptos_franja2[end]) : 0.0

    if balance_mode == :area
        for i in 1:num_deptos1
            push!(deptos_ordenados1, (get_area(deptos_franja1[i]), get_tipo(deptos_franja1[i])))
        end

        num_deptos2_half = div(num_deptos2, 2)
        for i in 1:num_deptos2_half
            push!(deptos_ordenados2, (get_area(deptos_franja2[i]), get_tipo(deptos_franja2[i])))
        end
        if tipo_escala == :exterior
            push!(deptos_ordenados2, (area_escala, -1))
        end
        for i in (num_deptos2_half + 1):num_deptos2
            push!(deptos_ordenados2, (get_area(deptos_franja2[i]), get_tipo(deptos_franja2[i])))
        end
    else
        if deptos_total >= 4
            push!(deptos_ordenados1, (get_area(deptos_franja1[2]), get_tipo(deptos_franja1[2])))
            if num_deptos1 > 2
                for i in 3:num_deptos1
                    push!(deptos_ordenados1, (get_area(deptos_franja1[i]), get_tipo(deptos_franja1[i])))
                end
            end
            push!(deptos_ordenados1, (get_area(deptos_franja1[1]), get_tipo(deptos_franja1[1])))

            num_deptos2_half = div(num_deptos2, 2)
            for i in 1:num_deptos2_half
                push!(deptos_ordenados2, (get_area(deptos_franja2[i]), get_tipo(deptos_franja2[i])))
            end
            if tipo_escala == :exterior
                push!(deptos_ordenados2, (area_escala, -1))
            end
            for i in (num_deptos2_half + 1):num_deptos2
                push!(deptos_ordenados2, (get_area(deptos_franja2[i]), get_tipo(deptos_franja2[i])))
            end
        else
            for depto in deptos_franja1
                push!(deptos_ordenados1, (get_area(depto), get_tipo(depto)))
            end
            num_deptos2_half = div(num_deptos2, 2)
            for i in 1:num_deptos2_half
                push!(deptos_ordenados2, (get_area(deptos_franja2[i]), get_tipo(deptos_franja2[i])))
            end
            if tipo_escala == :exterior
                push!(deptos_ordenados2, (area_escala, -1))
            end
            for i in (num_deptos2_half + 1):num_deptos2
                push!(deptos_ordenados2, (get_area(deptos_franja2[i]), get_tipo(deptos_franja2[i])))
            end
        end
    end

    return deptos_ordenados1, deptos_ordenados2
end

# ──────────────────────────────────────────────────────────────────────────────────
# Corridor and results packaging helpers
# ──────────────────────────────────────────────────────────────────────────────────

# Computes corridor geometry spanning both strips based on apartment coordinates
function calcula_geometria_pasillo(vec_coord_fin1::Vector{Float64}, vec_coord_fin2::Vector{Float64}, vec_coord_ini1::Vector{Float64}, vec_coord_ini2::Vector{Float64}, coord_base::Float64, ancho_pasillo::Float64, is_vertical::Bool, W::Float64, H::Float64, coord_min::Float64, min_largo_pasillo::Float64, pasillo_centrado::Bool, vec_tipo_deptos1::Vector{Int}, vec_tipo_deptos2::Vector{Int}, tipo_escala::Symbol, ancho_escala, area_escala)
    num_deptos_franja1 = count(t -> t != -1, vec_tipo_deptos1)
    num_deptos_franja2 = count(t -> t != -1, vec_tipo_deptos2)
    num_deptos_total = num_deptos_franja1 + num_deptos_franja2

    coord_ini_pasillo = min(vec_coord_fin1[1], vec_coord_fin2[1])
    coord_fin_pasillo = max(vec_coord_ini1[end], vec_coord_ini2[end])
    largo_pasillo = coord_fin_pasillo - coord_ini_pasillo

    if largo_pasillo < min_largo_pasillo
        centro_pasillo = (coord_ini_pasillo + coord_fin_pasillo) / 2
        coord_ini_pasillo = centro_pasillo - min_largo_pasillo / 2
        coord_fin_pasillo = centro_pasillo + min_largo_pasillo / 2
        largo_pasillo = min_largo_pasillo
    end

    if pasillo_centrado || num_deptos_total == 2
        if is_vertical
            centro_planta = coord_min + H / 2
        else
            centro_planta = coord_min + W / 2
        end

        if num_deptos_total == 2
            coord_ini_pasillo = centro_planta - largo_pasillo / 2
            coord_fin_pasillo = centro_planta + largo_pasillo / 2
        else
            if centro_planta < coord_ini_pasillo
                coord_ini_pasillo = centro_planta
            elseif centro_planta > coord_fin_pasillo
                coord_fin_pasillo = centro_planta
            end
        end

        largo_pasillo = coord_fin_pasillo - coord_ini_pasillo
    end

    coord_pasillo = coord_base - ancho_pasillo / 2

    if is_vertical
        ps_pasillo = polyShape.polyBox(coord_pasillo, coord_ini_pasillo, ancho_pasillo, largo_pasillo, 0.0)
        x_centroide = coord_base
        y_centroide = (coord_ini_pasillo + coord_fin_pasillo) / 2
    else
        ps_pasillo = polyShape.polyBox(coord_ini_pasillo, coord_pasillo, largo_pasillo, ancho_pasillo, 0.0)
        x_centroide = (coord_ini_pasillo + coord_fin_pasillo) / 2
        y_centroide = coord_base
    end

    largo_escala = area_escala / ancho_escala

    if tipo_escala == :interior
        if is_vertical
            ps_escala = polyShape.polyBox(x_centroide - largo_escala / 2, y_centroide - ancho_escala / 2, largo_escala, ancho_escala, 0.0)
        else
            ps_escala = polyShape.polyBox(x_centroide - ancho_escala / 2, y_centroide - largo_escala / 2, ancho_escala, largo_escala, 0.0)                
        end
        ps_pasillo = polyShape.polyUnion(ps_pasillo, ps_escala)
    end

    return coord_ini_pasillo, coord_fin_pasillo, largo_pasillo, ps_pasillo
end

# Packages all computed geometries and parameters into results dictionary
function empaqueta_resultados(num_deptos1::Int, num_deptos2::Int, deptos_ordenados1::Vector{Tuple{Float64, Int}}, deptos_ordenados2::Vector{Tuple{Float64, Int}}, dimension1::Float64, dimension2::Float64, W::Float64, H::Float64, ancho_pasillo::Float64, largo_pasillo::Float64, ps_pasillo::PolyShape, vec_ps_deptos1::Vector{PolyShape}, vec_ps_deptos2::Vector{PolyShape}, vec_dimension_deptos2::Vector{Float64}, vec_tipo_deptos2::Vector{Int}, area_escala::Float64, vec_terrazas1::Vector{PolyShape}, vec_terrazas2::Vector{PolyShape}, is_vertical::Bool, tipo_escala::Symbol)
    prefix1, prefix2 = is_vertical ? ("este", "oeste") : ("norte", "sur")
    dim_key = is_vertical ? "width" : "height"

    result = Dict(
        "feasible" => true,
        "status" => "LOCALLY_SOLVED",
        "n_apts_$prefix1" => num_deptos1,
        "n_apts_$prefix2" => num_deptos2,
        "vec_sup_deptos_$prefix1" => [get_area(apt) for apt in deptos_ordenados1],
        "vec_sup_deptos_$prefix2" => [get_area(apt) for apt in deptos_ordenados2 if get_tipo(apt) != -1],
        "$(dim_key)_$prefix1" => round(dimension1, digits=2),
        "$(dim_key)_$prefix2" => round(dimension2, digits=2),
        "floor_width" => W,
        "floor_height" => H,
        "ancho_pasillo" => ancho_pasillo,
        "largo_pasillo" => largo_pasillo,
        "ps_pasillo" => deepcopy(ps_pasillo)
    )

    if tipo_escala == :exterior
        id_escala = findfirst(==(- 1), vec_tipo_deptos2)
        id_escala === nothing && error("No staircase found in strip 2 (tipo_depto == -1)")

        num_escalas = count(==(- 1), vec_tipo_deptos2)
        num_escalas > 1 && @warn "Multiple staircases found in strip 2 (count=$num_escalas). Using first occurrence at index $id_escala"

        ps_escala = vec_ps_deptos2[id_escala]
        dimension_escala = vec_dimension_deptos2[id_escala]

        vec_ps_deptos2_sin_escala = [vec_ps_deptos2[i] for i in eachindex(vec_ps_deptos2) if i != id_escala]
        vec_terrazas2_sin_escala = [vec_terrazas2[i] for i in eachindex(vec_terrazas2) if i != id_escala]

        result["ps_escala"] = deepcopy(ps_escala)
        result["ancho_escala"] = round(dimension2, digits=2)
        result["alto_escala"] = round(dimension_escala, digits=2)
        result["area_escala"] = round(area_escala, digits=2)
        result["vec_polyshapes_all"] = vcat(deepcopy(vec_ps_deptos1), deepcopy(vec_ps_deptos2_sin_escala))
        result["vec_terrazas_all"] = vcat(deepcopy(vec_terrazas1), deepcopy(vec_terrazas2_sin_escala))
    elseif tipo_escala == :interior || tipo_escala == :none
        result["ps_escala"] = nothing
        result["ancho_escala"] = nothing
        result["alto_escala"] = nothing
        result["area_escala"] = nothing
        result["vec_polyshapes_all"] = vcat(deepcopy(vec_ps_deptos1), deepcopy(vec_ps_deptos2))
        result["vec_terrazas_all"] = vcat(deepcopy(vec_terrazas1), deepcopy(vec_terrazas2))
    end

    return result
end

# Checks if all terraces are fully contained within floor plan boundaries
function verifica_inscripcion_terrazas(ps_planta::PolyShape, vec_terrazas::Vector{PolyShape})
    for terraza in vec_terrazas
        inters = polyShape.polyIntersection(ps_planta, terraza)
        area_inters = polyShape.polyArea(inters)
        area_terraza = polyShape.polyArea(terraza)
        if abs(area_inters - area_terraza) > .1
            return false
        end
    end

    return true
end

# ──────────────────────────────────────────────────────────────────────────────────
# High-level computation functions
# ──────────────────────────────────────────────────────────────────────────────────

# Prepares normalized floor plan, distributes apartments, and calculates strip dimensions
function prepare_floor_inputs(ps_planta::PolyShape, vec_sup_deptos::Vector{Float64}, vec_num_deptos::Vector{Int}, area_escala::Float64, ancho_pasillo::Float64, balance_mode::Symbol, is_vertical::Bool, tipo_escala::Symbol, max_ancho_terraza::Float64)

    W, H, vec_x_planta, vec_y_planta, angulo_rotacion, cr, ps_planta_normalizado = normaliza_planta_rectangular(ps_planta)

    deptos_total = sum(vec_num_deptos)
    deptos_franja1, deptos_franja2, area_franja1, area_franja2 = distribuye_deptos_entre_franjas(vec_sup_deptos, vec_num_deptos, area_escala, tipo_escala)

    dimension_depto1, dimension_depto2 = calcula_dimensiones_franjas(area_franja1, area_franja2, W, H, ancho_pasillo, max_ancho_terraza, is_vertical)

    coord_min_x = minimum(vec_x_planta)
    coord_min_y = minimum(vec_y_planta)

    if is_vertical
        total_dimension1_utilizada = max_ancho_terraza + dimension_depto1 + ancho_pasillo / 2
        total_dimension2_utilizada = max_ancho_terraza + dimension_depto2 + ancho_pasillo / 2
        total_dimension_utilizada = total_dimension1_utilizada + total_dimension2_utilizada
        holgura = W - total_dimension_utilizada
        coord_min_x += max_ancho_terraza + holgura/2
    else
        total_dimension1_utilizada = max_ancho_terraza + dimension_depto1 + ancho_pasillo / 2
        total_dimension2_utilizada = max_ancho_terraza + dimension_depto2 + ancho_pasillo / 2
        total_dimension_utilizada = total_dimension1_utilizada + total_dimension2_utilizada
        holgura = H - total_dimension_utilizada
        coord_min_y += max_ancho_terraza + holgura/2
    end

    deptos_ordenados1, deptos_ordenados2 = ordena_deptos_en_franja(deptos_franja1, deptos_franja2, deptos_total, tipo_escala, balance_mode=balance_mode)

    return (W=W, H=H, vec_x_planta=vec_x_planta, vec_y_planta=vec_y_planta, angulo_rotacion=angulo_rotacion,
            cr=cr, ps_planta_normalizado=ps_planta_normalizado, deptos_ordenados1=deptos_ordenados1,
            deptos_ordenados2=deptos_ordenados2, dimension_depto1=dimension_depto1, dimension_depto2=dimension_depto2,
            coord_min_x=coord_min_x, coord_min_y=coord_min_y, dimension_terraza_max=max_ancho_terraza,
            total_dimension1_utilizada=total_dimension1_utilizada, total_dimension2_utilizada=total_dimension2_utilizada)
end


# ──────────────────────────────────────────────────────────────────────────────────
# Stage 1: Input preparation and normalization
# ──────────────────────────────────────────────────────────────────────────────────
planta_normalizada = prepare_floor_inputs(ps_planta, vec_sup_deptos, vec_num_deptos, 
                                    area_escala, ancho_pasillo, 
                                balance_mode, is_vertical, tipo_escala, max_ancho_terraza)

# ──────────────────────────────────────────────────────────────────────────────────
# Stage 2: Strip geometry computation
# ──────────────────────────────────────────────────────────────────────────────────
if is_vertical
    coord_base = planta_normalizada.coord_min_x + planta_normalizada.dimension_depto2
    coord_disponible = planta_normalizada.H
    coord_min = planta_normalizada.coord_min_y
    franja1 = :este
    franja2 = :oeste
else
    coord_base = planta_normalizada.coord_min_y + planta_normalizada.dimension_depto2
    coord_disponible = planta_normalizada.W
    coord_min = planta_normalizada.coord_min_x
    franja1 = :norte
    franja2 = :sur
end

vec_coord_ini1, vec_coord_fin1, vec_dimension1_deptos1, vec_dimension2_deptos1, vec_tipo_deptos1, 
        vec_ps_deptos1_normalizado = genera_deptos_franja(planta_normalizada.deptos_ordenados1, coord_min, 
                                        planta_normalizada.dimension_depto1, coord_disponible, min_ancho_escala, 
                                        is_vertical, coord_base, franja1)
vec_coord_ini2, vec_coord_fin2, vec_dimension1_deptos2, vec_dimension2_deptos2, vec_tipo_deptos2, 
        vec_ps_deptos2_normalizado = genera_deptos_franja(planta_normalizada.deptos_ordenados2, coord_min, 
                                        planta_normalizada.dimension_depto2, coord_disponible, min_ancho_escala, 
                                        is_vertical, coord_base, franja2)

coord_ini_pasillo, coord_fin_pasillo, largo_pasillo, ps_pasillo_normalizado = calcula_geometria_pasillo(
                                        vec_coord_fin1, vec_coord_fin2, vec_coord_ini1, vec_coord_ini2, 
                                        coord_base, ancho_pasillo, is_vertical, 
                                        planta_normalizada.W, planta_normalizada.H, 
                                        coord_min, min_largo_pasillo, pasillo_centrado, 
                                        vec_tipo_deptos1, vec_tipo_deptos2, 
                                        tipo_escala, min_ancho_escala, area_escala)

vec_ps_deptos1_normalizado, vec_extension_dimension1_1 = extiende_deptos_con_interseccion_pasillo(vec_coord_ini1, vec_coord_fin1, vec_dimension1_deptos1, vec_dimension2_deptos1, coord_base, ps_pasillo_normalizado, franja1, is_vertical, vec_ps_deptos1_normalizado, ps_pasillo_normalizado)
vec_ps_deptos2_normalizado, vec_extension_dimension1_2 = extiende_deptos_con_interseccion_pasillo(vec_coord_ini2, vec_coord_fin2, vec_dimension1_deptos2, vec_dimension2_deptos2, coord_base, ps_pasillo_normalizado, franja2, is_vertical, vec_ps_deptos2_normalizado, ps_pasillo_normalizado)

vec_terrazas1_normalizado = PolyShape[]
vec_terrazas2_normalizado = PolyShape[]

if !isempty(vec_sup_terraza)
    if is_vertical
        coord_terrace_base1 = [coord_base + vec_dimension1_deptos1[i] + vec_extension_dimension1_1[i] for i in eachindex(planta_normalizada.deptos_ordenados1)]
        vec_terrazas1_normalizado = genera_terrazas_franja(planta_normalizada.deptos_ordenados1, vec_sup_terraza, vec_dimension2_deptos1, vec_coord_ini1, coord_terrace_base1, franja1, planta_normalizada.dimension_terraza_max, is_vertical)

        coord_terrace_base2 = [coord_base - vec_dimension1_deptos2[i] - vec_extension_dimension1_2[i] for i in eachindex(planta_normalizada.deptos_ordenados2)]
        vec_terrazas2_normalizado = genera_terrazas_franja(planta_normalizada.deptos_ordenados2, vec_sup_terraza, vec_dimension2_deptos2, vec_coord_ini2, coord_terrace_base2, franja2, planta_normalizada.dimension_terraza_max, is_vertical)

        flag_inscripcion1 = verifica_inscripcion_terrazas(planta_normalizada.ps_planta_normalizado, vec_terrazas1_normalizado)
        flag_inscripcion2 = verifica_inscripcion_terrazas(planta_normalizada.ps_planta_normalizado, vec_terrazas2_normalizado)

        if !flag_inscripcion1 && !flag_inscripcion2
            @warn "Both strips have outbound terraces - layout may not fit properly"
        end

        if !flag_inscripcion1
            vec_ps_deptos1_normalizado, vec_ps_deptos2_normalizado, vec_terrazas1_normalizado, vec_terrazas2_normalizado, ps_pasillo_normalizado =
                correct_outbound_terraces(vec_terrazas1_normalizado, vec_terrazas2_normalizado,
                                            vec_ps_deptos1_normalizado, vec_ps_deptos2_normalizado,
                                            ps_pasillo_normalizado, planta_normalizada.vec_x_planta, true, true, true)
        end
        if !flag_inscripcion2
            vec_ps_deptos1_normalizado, vec_ps_deptos2_normalizado, vec_terrazas1_normalizado, vec_terrazas2_normalizado, ps_pasillo_normalizado =
                correct_outbound_terraces(vec_terrazas1_normalizado, vec_terrazas2_normalizado,
                                            vec_ps_deptos1_normalizado, vec_ps_deptos2_normalizado,
                                            ps_pasillo_normalizado, planta_normalizada.vec_x_planta, true, false, false)
        end
    else
        coord_terrace_base1 = [coord_base + vec_dimension1_deptos1[i] + vec_extension_dimension1_1[i] for i in eachindex(planta_normalizada.deptos_ordenados1)]
        vec_terrazas1_normalizado = genera_terrazas_franja(planta_normalizada.deptos_ordenados1, vec_sup_terraza, vec_dimension2_deptos1, vec_coord_ini1, coord_terrace_base1, franja1, planta_normalizada.dimension_terraza_max, is_vertical)

        coord_terrace_base2 = [coord_base - vec_dimension1_deptos2[i] - vec_extension_dimension1_2[i] for i in eachindex(planta_normalizada.deptos_ordenados2)]
        vec_terrazas2_normalizado = genera_terrazas_franja(planta_normalizada.deptos_ordenados2, vec_sup_terraza, vec_dimension2_deptos2, vec_coord_ini2, coord_terrace_base2, franja2, planta_normalizada.dimension_terraza_max, is_vertical)

        flag_inscripcion1 = verifica_inscripcion_terrazas(planta_normalizada.ps_planta_normalizado, vec_terrazas1_normalizado)
        flag_inscripcion2 = verifica_inscripcion_terrazas(planta_normalizada.ps_planta_normalizado, vec_terrazas2_normalizado)

        if !flag_inscripcion1 && !flag_inscripcion2
            @warn "Both strips have outbound terraces - layout may not fit properly"
        end

        if !flag_inscripcion1
            vec_ps_deptos1_normalizado, vec_ps_deptos2_normalizado, vec_terrazas1_normalizado, vec_terrazas2_normalizado, ps_pasillo_normalizado =
                correct_outbound_terraces(vec_terrazas1_normalizado, vec_terrazas2_normalizado,
                                            vec_ps_deptos1_normalizado, vec_ps_deptos2_normalizado,
                                            ps_pasillo_normalizado, planta_normalizada.vec_y_planta, false, true, true)
        end
        if !flag_inscripcion2
            vec_ps_deptos1_normalizado, vec_ps_deptos2_normalizado, vec_terrazas1_normalizado, vec_terrazas2_normalizado, ps_pasillo_normalizado =
                correct_outbound_terraces(vec_terrazas1_normalizado, vec_terrazas2_normalizado,
                                            vec_ps_deptos1_normalizado, vec_ps_deptos2_normalizado,
                                            ps_pasillo_normalizado, planta_normalizada.vec_y_planta, false, false, false)
        end
    end
end

franjas_computadas = (vec_ps_deptos1_normalizado=vec_ps_deptos1_normalizado, vec_ps_deptos2_normalizado=vec_ps_deptos2_normalizado,
        vec_terrazas1_normalizado=vec_terrazas1_normalizado, vec_terrazas2_normalizado=vec_terrazas2_normalizado,
        ps_pasillo_normalizado=ps_pasillo_normalizado, largo_pasillo=largo_pasillo,
        vec_dimension_deptos2=vec_dimension2_deptos2, vec_tipo_deptos2=vec_tipo_deptos2)

# ──────────────────────────────────────────────────────────────────────────────────
# Stage 3: Rotation back to original coordinates
# ──────────────────────────────────────────────────────────────────────────────────
vec_ps_deptos1 = rota_polyshapes(franjas_computadas.vec_ps_deptos1_normalizado, planta_normalizada.angulo_rotacion, planta_normalizada.cr)
vec_ps_deptos2 = rota_polyshapes(franjas_computadas.vec_ps_deptos2_normalizado, planta_normalizada.angulo_rotacion, planta_normalizada.cr)
vec_terrazas1 = rota_polyshapes(franjas_computadas.vec_terrazas1_normalizado, planta_normalizada.angulo_rotacion, planta_normalizada.cr)
vec_terrazas2 = rota_polyshapes(franjas_computadas.vec_terrazas2_normalizado, planta_normalizada.angulo_rotacion, planta_normalizada.cr)
ps_pasillo = polyShape.polyRotate(franjas_computadas.ps_pasillo_normalizado, -planta_normalizada.angulo_rotacion, planta_normalizada.cr)

# ──────────────────────────────────────────────────────────────────────────────────
# Stage 4: Results packaging
# ──────────────────────────────────────────────────────────────────────────────────

num_deptos1 = length(planta_normalizada.deptos_ordenados1)
num_deptos2 = (tipo_escala == :exterior) ? length(planta_normalizada.deptos_ordenados2) - 1 : length(planta_normalizada.deptos_ordenados2)

results_2 = empaqueta_resultados(num_deptos1, num_deptos2, planta_normalizada.deptos_ordenados1, planta_normalizada.deptos_ordenados2,
                                planta_normalizada.dimension_depto1, planta_normalizada.dimension_depto2, planta_normalizada.W, planta_normalizada.H, ancho_pasillo, franjas_computadas.largo_pasillo, ps_pasillo,
                                vec_ps_deptos1, vec_ps_deptos2, franjas_computadas.vec_dimension_deptos2, franjas_computadas.vec_tipo_deptos2,
                                area_escala, vec_terrazas1, vec_terrazas2, is_vertical, tipo_escala)

