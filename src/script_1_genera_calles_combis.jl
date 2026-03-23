# ═══════════════════════════════════════════════════════════════════════════════
# DATABASE CONNECTION & AWS INFRASTRUCTURE SETUP
# ═══════════════════════════════════════════════════════════════════════════════
using LandValue, DotEnv, DataFrames, CSV, Statistics

my_env = DotEnv.config("secrets.env")
conn_aws = aws_julia.connection(my_env["AWS_ACCESS_KEY"], my_env["AWS_SECRET_KEY"], my_env["AWS_REGION"])

key_pair   = "neo4j-key-pair.pem"
ec2_user   = "ec2-user"

INSTANCIA_EC2 = "Neo4j-EC2-V2"
instance_info = aws_julia.find_instance_by_name(INSTANCIA_EC2, conn_aws)
public_dns = instance_info["dnsName"]

folder = "/usr/bin/cypher-shell"
neo4j_host = my_env["NEO4J_URI"]
neo4j_user = my_env["NEO4J_USER"]
neo4j_password = my_env["NEO4J_PASSWORD"]

conn_neo4j = neo4j_julia.connection(neo4j_host, neo4j_user, neo4j_password, folder, key_pair, ec2_user, public_dns)


# ═══════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS: COORDINATE TRANSFORMS
# ═══════════════════════════════════════════════════════════════════════════════

function wkt4326_to_local(wkt, dx, dy)
    geom = polyGdal.astext2shape(wkt)
    geom = polyShape.shape_4326to32719(geom)
    geom = polyShape.ajustaCoordenadas(geom, dx, dy)
    return geom
end

function local_to_4326(geom, dx, dy)
    geom_32719 = polyShape.ajustaCoordenadasInversa(geom, dx, dy)
    geom_4326 = polyShape.shape_32719to4326(geom_32719)
    return geom_4326, geom_32719
end

function parse_list_predios(list_predios_str)
    return split(strip(list_predios_str, ['(', ')']), ";")
end

function stitch_street_segments_together(id_val, df_calles, id_col, dict_geom_local, dx, dy)
    vec_segmento_calle = unique(df_calles[df_calles[!, id_col] .== id_val, "id_segmento_calle"])

    df_calles_filtered = df_calles[df_calles[!, id_col] .== id_val, :]
    ps_calles_combi = wkt4326_to_local(df_calles_filtered[:, "geom_wkt"], dx, dy)
    ps_calles_combi = polyShape.setPolyOrientation(ps_calles_combi, 1)

    num_segmentos = ps_calles_combi.NumRegions

    ps_combi = dict_geom_local[id_val]

    ps_calles = PolyShape([], 0)
    for i = 1:num_segmentos
        i_prev = mod1(i - 1, num_segmentos)

        num_edges = df_calles_filtered[i, "num_edges"][1]
        edge_i = df_calles_filtered[i, "id_edge"][1]
        edge_i_prev = df_calles_filtered[i_prev, "id_edge"][1]

        if edge_i_prev == mod1(edge_i - 1, num_edges)

            ps_i_prev = polyShape.subShape(ps_calles_combi, i_prev)
            ps_i = polyShape.subShape(ps_calles_combi, i)

            ps_inter_i_prev = polyShape.polyIntersection(ps_i, ps_i_prev)
            if polyShape.polyArea(ps_inter_i_prev) <= 5
                ps_i_ext = polyShape.polyHasnan(polyShape.partialPolyOffset(ps_i, [2], 40)) ? deepcopy(ps_i) : polyShape.partialPolyOffset(ps_i, [2], 40)
                ps_i_prev_ext = polyShape.polyHasnan(polyShape.partialPolyOffset(ps_i_prev, [4], 40)) ? deepcopy(ps_i_prev) : polyShape.partialPolyOffset(ps_i_prev, [4], 40)
                ps_ext_inter = polyShape.polyIntersection(ps_i_ext, ps_i_prev_ext)
                if !isempty(ps_ext_inter.Vertices)
                    aux = polyShape.polyHasnan(polyShape.partialPolyOffset(ps_i, [3, 4], [10, 40])) ? deepcopy(ps_i) : polyShape.partialPolyOffset(ps_i, [3, 4], [10, 40])
                    ps_ext_inter_ = polyShape.polyDifference(ps_ext_inter, aux)
                    aux = polyShape.polyHasnan(polyShape.partialPolyOffset(ps_i_prev, [2, 3], [40, 10])) ? deepcopy(ps_i_prev) : polyShape.partialPolyOffset(ps_i_prev, [2, 3], [40, 10])
                    ps_ext_inter_ = polyShape.polyDifference(ps_ext_inter_, aux)
                    if ps_ext_inter_.NumRegions >= 1
                        ps_ext_inter = deepcopy(ps_ext_inter_)
                    end

                    ps_i_aux = polyShape.convHull(PolyShape([[ps_ext_inter.Vertices[1]; ps_i.Vertices[1]]],1))
                    ps_i_prev_aux = polyShape.convHull(PolyShape([[ps_ext_inter.Vertices[1]; ps_i_prev.Vertices[1]]],1))
                    ps_x = polyShape.polyUnion(ps_i_aux, ps_i_prev_aux)

                    if i == 1
                        ps_calles = deepcopy(ps_x)
                    else
                        ps_calles = polyShape.polyUnion(ps_calles, ps_x)
                    end
                end
            else
                if i == 1
                    ps_calles = deepcopy(ps_inter_i_prev)
                else
                    ps_calles = polyShape.polyUnion(ps_calles, ps_inter_i_prev)
                end
            end
        else
            if i == 1
                ps_calles = deepcopy(polyShape.subShape(ps_calles_combi, i))
            else
                ps_calles = polyShape.polyUnion(ps_calles, polyShape.subShape(ps_calles_combi, i))
            end
        end
    end

    return ps_calles, ps_combi, vec_segmento_calle
end


# ═══════════════════════════════════════════════════════════════════════════════
# HELPER: BOUNDING BOX SPATIAL INDEX
# ═══════════════════════════════════════════════════════════════════════════════

function compute_bbox(geom)
    xmin, ymin = Inf, Inf
    xmax, ymax = -Inf, -Inf
    verts = geom.Vertices
    for V in verts
        xmin = min(xmin, minimum(V[:, 1]))
        xmax = max(xmax, maximum(V[:, 1]))
        ymin = min(ymin, minimum(V[:, 2]))
        ymax = max(ymax, maximum(V[:, 2]))
    end
    return (xmin=xmin, ymin=ymin, xmax=xmax, ymax=ymax)
end

function bbox_overlaps(a, b)
    return a.xmin <= b.xmax && a.xmax >= b.xmin && a.ymin <= b.ymax && a.ymax >= b.ymin
end

function find_candidate_segments(box_bbox, segment_bboxes)
    return findall(sb -> bbox_overlaps(box_bbox, sb), segment_bboxes)
end


# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════
comunas = ["vitacura", "la_florida", "santiago", "providencia", "las_condes", "nunoa"]
const BOX_HEIGHT = 30

sup_combi_sii_min = 800;    sup_combi_sii_max = 4000
length_min_combi = 38;      length_max_combi = 120
width_min_combi = 20;       width_max_combi = 65
length_to_width_min = 1;    length_to_width_max = 5.0
rectangularity_min = 0.95;  rectangularity_max = 1
convexity_min = 0.95;       convexity_max = 1
num_predios_min = 1;        num_predios_max = 12

aws_bucket = "landengines-data"

function upload_and_cleanup(df, local_file_name, conn_aws, aws_bucket)
    CSV.write(local_file_name, df)
    println("Processing complete. Final data saved to ", local_file_name)
    aws_file_name = "kg/$(local_file_name)"
    aws_julia.upload_csv_file_to_s3(conn_aws, aws_bucket, aws_file_name, local_file_name)
    if isfile(local_file_name)
        rm(local_file_name)
        println("$(local_file_name) Checkpoint file erased.")
    end
end


# ═══════════════════════════════════════════════════════════════════════════════
# QUERY COMBIS (ONCE, ALL COMUNAS)
# ═══════════════════════════════════════════════════════════════════════════════
println("Querying all combis...")
query = """
MATCH (c:Combi)
WHERE
c.length >= $length_min_combi             AND c.length <= $length_max_combi
AND c.width >= $width_min_combi                 AND c.width <= $width_max_combi
AND c.length_to_width >= $length_to_width_min   AND c.length_to_width <= $length_to_width_max
AND c.rectangularity >= $rectangularity_min     AND c.rectangularity <= $rectangularity_max
AND c.convexity >= $convexity_min               AND c.convexity <= $convexity_max
RETURN DISTINCT  c.manzent AS manzent, c.id_combi AS id_combi, c.predios AS list_predios,
c.rectangularity AS rectangularity, c.convexity AS convexity, c.length AS length, c.width AS width,
c.geom_combi AS geom_wkt, c.comuna AS comuna
ORDER BY comuna, manzent, id_combi
"""
df_all_combis = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
println("Total combis: $(nrow(df_all_combis)) rows")


# ═══════════════════════════════════════════════════════════════════════════════
# GLOBAL ACCUMULATORS
# ═══════════════════════════════════════════════════════════════════════════════
all_calles_predios = []
all_predio_to_calles_predio = []
all_segmento_calle_to_calles_predio = []
all_calles_combis = []
all_segmento_calle_to_calles_combi = []
all_combi_to_calles_combi = []
all_calles_contexto_combis = []


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN LOOP: PROCESS COMUNA BY COMUNA
# ═══════════════════════════════════════════════════════════════════════════════
for comuna in comunas
local query, df_semento_calle, df_combis, df_predios, df_predios_comuna, df_areas_verdes
local ls_segmentos, dx, dy, ps_segmentos, segment_bboxes
local dict_combis_local, manzanas_unicas, dict_predios_manzana_local
local ps_predios_comuna, ps_areas_verdes, predios_in_combis, dict_predios_local
local df_predios_filtered, vec_box_calle_predio, df_box_calle_predio
local data_calles_predios, lista_predios_filtered, predios_con_boxes
local df_calles_predios, df_segmento_calle_to_calles_predio, df_predio_to_calles_predio
local vec_box_calle_combi, df_box_calle_combi
local data_calles_combis, df_calles_combis
local df_segmento_calle_to_calles_combi, df_combi_to_calles_combi
local data_calles_contexto_combis, df_calles_contexto_combis
println("═══════════════════════════════════════════════════════════════")
println("═══ Processing comuna: $(comuna) ═══")
println("═══════════════════════════════════════════════════════════════")


# ─── QUERY PHASE ─────────────────────────────────────────────────────────────

println("[$(comuna)] Querying segmentos de calle...")
query = """
MATCH (n:Segmento_Calle)
WHERE n.comuna = '$(comuna)'
RETURN n.codigo_calle AS codigo_calle,
n.codigo_comuna AS codigo_comuna,
n.comuna AS comuna,
n.geom_wkt AS geom_wkt,
n.id_segmento_calle AS id_segmento_calle,
n.nombre_calle AS nombre_calle,
n.tipo_calle AS tipo_calle
"""
df_semento_calle = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
println("[$(comuna)] Segmentos de calle: $(nrow(df_semento_calle)) rows")

println("[$(comuna)] Querying predios...")
query = """
    MATCH (m:Manzana)<-[:SE_UBICA_EN_MANZANA]-(p:Predio)-[:TIENE_GEOM]->(gp:Geom_Predio)
    WHERE p.comuna = '$(comuna)'
    RETURN p.codigo_predial AS codigo_predial, p.comuna AS comuna, m.manzent AS manzent, gp.geom_wkt AS geom_wkt
"""
df_predios = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
println("[$(comuna)] Predios: $(nrow(df_predios)) rows")

println("[$(comuna)] Filtering combis by predios...")
predios_comuna_set = Set{String}(string.(df_predios[:, "codigo_predial"]))
df_combis = filter(r -> any(p -> p in predios_comuna_set, String.(parse_list_predios(r.list_predios))), df_all_combis)
println("[$(comuna)] Combis: $(nrow(df_combis)) rows")

if nrow(df_combis) == 0
    println("[$(comuna)] No combis found, skipping comuna")
    continue
end

println("[$(comuna)] Querying predios comuna (geom only)...")
query = """
MATCH (gp:Geom_Predio)<-[:TIENE_GEOM]-(p:Predio)
WHERE p.comuna = '$(comuna)'
RETURN DISTINCT gp.geom_wkt AS geom_wkt
"""
df_predios_comuna = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
println("[$(comuna)] Predios comuna: $(nrow(df_predios_comuna)) rows")

println("[$(comuna)] Querying areas verdes...")
query = """
MATCH (cat:Poi_Category)<-[:ES_POI_TIPO]-(poi:Poi)
WHERE cat.poi_category in ['park', 'garden'] AND poi.comuna = '$(comuna)'
RETURN poi.geom_wkt AS geom_wkt
"""
df_areas_verdes = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
println("[$(comuna)] Areas verdes: $(nrow(df_areas_verdes)) rows")


# ─── TRANSFORM PHASE ─────────────────────────────────────────────────────────

println("[$(comuna)] Transformando segmentos de calle a coordenadas locales...")
ls_segmentos = polyGdal.astext2shape(df_semento_calle[:, "geom_wkt"])
ls_segmentos = polyShape.shape_4326to32719(ls_segmentos)
ls_segmentos, dx, dy = polyShape.ajustaCoordenadas(ls_segmentos)
ps_segmentos = polyShape.lines2Polygons(ls_segmentos, 45)
println("[$(comuna)] Segmentos transformados: $(ls_segmentos.NumLines) lines")

println("[$(comuna)] Calculando bounding boxes de segmentos...")
segment_bboxes = [compute_bbox(polyShape.subShape(ls_segmentos, j)) for j in 1:ls_segmentos.NumLines]

println("[$(comuna)] Transformando combis a coordenadas locales ($(nrow(df_combis)))...")
dict_combis_local = Dict{String, PolyShape}()
for (i, row) in enumerate(eachrow(df_combis))
    ps = wkt4326_to_local(row.geom_wkt, dx, dy)
    dict_combis_local[row.id_combi] = polyShape.setPolyOrientation(ps, 1)
    i % 200 == 0 && println("[$(comuna)]   combis: $(i)/$(nrow(df_combis))")
end
println("[$(comuna)] Combis transformadas: $(length(dict_combis_local))")

manzanas_unicas = unique(df_predios[:, "manzent"])
println("[$(comuna)] Transformando predios por manzana a coordenadas locales ($(length(manzanas_unicas)))...")
dict_predios_manzana_local = Dict()
for (i, manzent) in enumerate(manzanas_unicas)
    wkts = df_predios[df_predios[!, "manzent"] .== manzent, "geom_wkt"]
    ps = wkt4326_to_local(wkts, dx, dy)
    dict_predios_manzana_local[manzent] = polyShape.polyUnion(polyShape.setPolyOrientation(ps, 1))
    i % 100 == 0 && println("[$(comuna)]   manzanas: $(i)/$(length(manzanas_unicas))")
end
println("[$(comuna)] Manzanas transformadas: $(length(dict_predios_manzana_local))")

println("[$(comuna)] Transformando predios comuna a coordenadas locales ($(nrow(df_predios_comuna)))...")
ps_predios_comuna = wkt4326_to_local(df_predios_comuna[:, "geom_wkt"], dx, dy)
ps_predios_comuna = polyShape.setPolyOrientation(ps_predios_comuna, 1)
println("[$(comuna)] Predios comuna transformados")

println("[$(comuna)] Transformando areas verdes a coordenadas locales ($(nrow(df_areas_verdes)))...")
ps_areas_verdes = wkt4326_to_local(df_areas_verdes[:, "geom_wkt"], dx, dy)
ps_areas_verdes = polyShape.setPolyOrientation(ps_areas_verdes, 1)
println("[$(comuna)] Areas verdes transformadas")

println("[$(comuna)] Identificando predios que participan en combis...")
predios_in_combis = Set{String}()
for row in eachrow(df_combis)
    union!(predios_in_combis, String.(parse_list_predios(row.list_predios)))
end
println("[$(comuna)] Predios en combis: $(length(predios_in_combis))")

println("[$(comuna)] Transformando predios individuales a coordenadas locales...")
dict_predios_local = Dict{String, PolyShape}()
for row in eachrow(df_predios)
    cp = string(row.codigo_predial)
    if cp in predios_in_combis
        ps = wkt4326_to_local(row.geom_wkt, dx, dy)
        dict_predios_local[cp] = polyShape.setPolyOrientation(ps, 1)
    end
end
println("[$(comuna)] Predios transformados: $(length(dict_predios_local))")


# ─── PHASE A: GENERA BOXES PARA CADA PREDIO ─────────────────────────────────

df_predios_filtered = filter(r -> string(r.codigo_predial) in predios_in_combis, df_predios)
vec_box_calle_predio = []

for (i, row) in enumerate(eachrow(df_predios_filtered))
    println("[$(comuna)] Processing predio $(i)/$(nrow(df_predios_filtered)): $(row.codigo_predial)")

    codigo_predial = string(row.codigo_predial)
    ps_predio_i = dict_predios_local[codigo_predial]
    ps_hull_i = polyShape.setPolyOrientation(polyShape.polySimplify(ps_predio_i, 1), 1)
    num_sides_hull_i = size(ps_hull_i.Vertices[1], 1)

    manzent_i = row.manzent
    ps_predios_manzana_i = dict_predios_manzana_local[manzent_i]

    for edge = 1:num_sides_hull_i

        box_check = polyShape.polyBoxFromEdge(ps_hull_i, edge, 5)
        if polyShape.polyArea(polyShape.polyIntersection(box_check, ps_predios_manzana_i)) <= 3
            box_i_edge = polyShape.polyBoxFromEdge(ps_hull_i, edge, BOX_HEIGHT)
            box_i_edge = polyShape.rotate_to_first_ccw(box_i_edge, box_i_edge.Vertices[1][1,:])

            box_offset = polyShape.partialPolyOffset(box_i_edge, [1], 5)
            box_bbox = compute_bbox(box_offset)
            candidates = find_candidate_segments(box_bbox, segment_bboxes)

            for j in candidates
                seg_row = eachrow(df_semento_calle)[j]
                seg_id = seg_row.id_segmento_calle
                ls_segmento_j = polyShape.subShape(ls_segmentos, j)

                flag_touches = polyGdal.shapeTouches(box_offset, ls_segmento_j)
                if flag_touches
                    box_i_edge_4326, _ = local_to_4326(box_i_edge, dx, dy)

                    push!(vec_box_calle_predio, (
                        codigo_predial = codigo_predial,
                        manzent = manzent_i,
                        id_segmento_calle = seg_id,
                        codigo_calle = seg_row.codigo_calle,
                        nombre_calle = seg_row.nombre_calle,
                        tipo_calle = seg_row.tipo_calle,
                        id_edge = edge,
                        num_edges = num_sides_hull_i,
                        edge = "[$(box_i_edge_4326.Vertices[1][1,1]), $(box_i_edge_4326.Vertices[1][1,2])]",
                        geom_wkt = polyShape.polyshape2wkt(box_i_edge_4326)
                    ))
                end
            end
        end
    end

    if i % 50 == 0 && !isempty(vec_box_calle_predio)
        println("[$(comuna)] Saving checkpoint at iteration $(i)...")
        df_checkpoint = DataFrame(vec_box_calle_predio)
        CSV.write("box_calle_predio.csv", df_checkpoint)
        println("[$(comuna)] Checkpoint saved with $(nrow(df_checkpoint)) records")
    end
end

df_box_calle_predio = DataFrame(vec_box_calle_predio)
df_box_calle_predio = unique(df_box_calle_predio)
println("[$(comuna)] Phase A complete: $(nrow(df_box_calle_predio)) box_calle_predio records")


# ─── PHASE A.2: GENERA df_calles_predios (STITCHED STREET POLYGONS PER PREDIO)

data_calles_predios = []
lista_predios_filtered = unique(string.(df_predios_filtered[:, "codigo_predial"]))
predios_con_boxes = nrow(df_box_calle_predio) > 0 ? Set{String}(df_box_calle_predio[:, "codigo_predial"]) : Set{String}()

for (i, codigo_predial) in enumerate(lista_predios_filtered)
    println("[$(comuna)] Processing calles predio $(i)/$(length(lista_predios_filtered)): $(codigo_predial)")

    if !(codigo_predial in predios_con_boxes)
        continue
    end

    try
        ps_calles_i, ps_predio_i, vec_segmento_calle = stitch_street_segments_together(codigo_predial, df_box_calle_predio, "codigo_predial", dict_predios_local, dx, dy)

        flag_calle_x_vecinos, mat_flag_calle_x_vecinos = polyShape.polyIntersects(ps_calles_i, ps_predios_comuna, true)
        ps_predios_comuna_i = polyShape.subShape(ps_predios_comuna, findall(any(mat_flag_calle_x_vecinos, dims=1)[:]))
        ps_calles_i = polyShape.polyDifference(ps_calles_i, ps_predios_comuna_i)

        flag_verde_x_vecinos, mat_flag_verde_x_vecinos = polyShape.polyIntersects(ps_calles_i, ps_areas_verdes, true)
        ps_areas_verdes_i = polyShape.subShape(ps_areas_verdes, findall(any(mat_flag_verde_x_vecinos, dims=1)[:]))
        ps_calles_i = polyShape.polyDifference(ps_calles_i, ps_areas_verdes_i)

        df_segmentos_predio = filter(r -> r.id_segmento_calle in vec_segmento_calle, df_semento_calle)
        ls_segmentos_predio = wkt4326_to_local(df_segmentos_predio[:, "geom_wkt"], dx, dy)

        for j = 1:ps_calles_i.NumRegions
            ps_calles_j = polyShape.subShape(ps_calles_i, j)

            flag_intersects, mat_intersects = polyShape.polyIntersects(ps_calles_j, ls_segmentos_predio, true)
            intersecting_indices = findall(any(mat_intersects, dims=1)[:])

            if !isempty(intersecting_indices)
                intersecting_segments = df_segmentos_predio[intersecting_indices, "id_segmento_calle"]
                intersecting_segment_names = df_segmentos_predio[intersecting_indices, "nombre_calle"]
                segmento_calle_intersecting = "[" * join(intersecting_segments, ", ") * "]"
                nombre_calle_intersecting = "[" * join(unique(intersecting_segment_names), ", ") * "]"
            else
                segmento_calle_intersecting = "[]"
                nombre_calle_intersecting = "[]"
            end

            ps_calles_4326_j, ps_calles_32719_j = local_to_4326(ps_calles_j, dx, dy)

            push!(data_calles_predios, (
                id_calle_predio = codigo_predial * "_" * string(j),
                codigo_predial = codigo_predial,
                lista_segmento_calle = segmento_calle_intersecting,
                lista_nombre_calle = nombre_calle_intersecting,
                calles_4326_wkt = polyShape.polyshape2wkt(ps_calles_4326_j),
                calles_32719_wkt = polyShape.polyshape2wkt(ps_calles_32719_j)
            ))
        end
    catch e
        println("[$(comuna)] Error processing predio $(i)/$(length(lista_predios_filtered)): $(codigo_predial) - $e")
    end
end
df_calles_predios = DataFrame(data_calles_predios)
println("[$(comuna)] Phase A.2 complete: $(nrow(df_calles_predios)) calles_predios records")


# ─── PHASE A.3: GENERA RELACIONES PREDIO-CALLE ──────────────────────────────

df_segmento_calle_to_calles_predio = DataFrame(id_calle_predio=String[], id_segmento_calle=String[])
for row in eachrow(df_calles_predios)
    segmentos_str = replace(replace(row.lista_segmento_calle, "[" => ""), "]" => "")
    if segmentos_str != ""
        segmentos = strip.(split(segmentos_str, ","))
        for segmento in segmentos
            if segmento != ""
                push!(df_segmento_calle_to_calles_predio, (id_calle_predio=row.id_calle_predio, id_segmento_calle=segmento))
            end
        end
    end
end

df_predio_to_calles_predio = nrow(df_calles_predios) > 0 ? unique(df_calles_predios[:, ["codigo_predial", "id_calle_predio"]]) : DataFrame(codigo_predial=String[], id_calle_predio=String[])
println("[$(comuna)] Phase A.3 complete: $(nrow(df_segmento_calle_to_calles_predio)) segment relations, $(nrow(df_predio_to_calles_predio)) predio relations")


# ─── PHASE B: DERIVA BOXES DE COMBIS A PARTIR DE LOS PREDIOS ────────────────

vec_box_calle_combi = []

for (i, row) in enumerate(eachrow(df_combis))
    println("[$(comuna)] Aggregating combi $(i)/$(nrow(df_combis)): $(row.id_combi)")

    id_combi = row.id_combi
    predios_combi = Set{String}(String.(parse_list_predios(row.list_predios)))
    df_predio_calles = filter(r -> r.codigo_predial in predios_combi, df_box_calle_predio)

    if nrow(df_predio_calles) == 0
        continue
    end

    ps_combi_i = dict_combis_local[id_combi]
    ps_hull_i = polyShape.setPolyOrientation(polyShape.polySimplify(ps_combi_i, 1), 1)
    num_sides_hull_i = size(ps_hull_i.Vertices[1], 1)

    edge_centers = Vector{Vector{Float64}}(undef, num_sides_hull_i)
    for edge = 1:num_sides_hull_i
        edge_box = polyShape.polyBoxFromEdge(ps_hull_i, edge, BOX_HEIGHT)
        edge_centers[edge] = [mean(edge_box.Vertices[1][:,1]), mean(edge_box.Vertices[1][:,2])]
    end

    for r in eachrow(df_predio_calles)
        box_local = wkt4326_to_local(r.geom_wkt, dx, dy)
        box_center = [mean(box_local.Vertices[1][:,1]), mean(box_local.Vertices[1][:,2])]

        best_edge = 1
        best_dist = Inf
        for edge = 1:num_sides_hull_i
            d = sum((box_center .- edge_centers[edge]).^2)
            if d < best_dist
                best_dist = d
                best_edge = edge
            end
        end

        push!(vec_box_calle_combi, (
            id_combi = id_combi,
            id_segmento_calle = r.id_segmento_calle,
            codigo_calle = r.codigo_calle,
            nombre_calle = r.nombre_calle,
            tipo_calle = r.tipo_calle,
            id_edge = best_edge,
            num_edges = num_sides_hull_i,
            edge = r.edge,
            geom_wkt = r.geom_wkt
        ))
    end
end

df_box_calle_combi = DataFrame(vec_box_calle_combi)
df_box_calle_combi = unique(df_box_calle_combi)
println("[$(comuna)] Phase B complete: $(nrow(df_box_calle_combi)) box_calle_combi records")


# ─── GENERA df_calles_combis ─────────────────────────────────────────────────

data_calles_combis = []
for (i, row) in enumerate(eachrow(df_combis))
    println("[$(comuna)] Processing calles combi $(i)/$(nrow(df_combis)): $(row.id_combi)")

    try
        id_combi = row.id_combi
        ps_calles_i, ps_combi_i, vec_segmento_calle = stitch_street_segments_together(id_combi, df_box_calle_combi, "id_combi", dict_combis_local, dx, dy)

        flag_calle_x_vecinos, mat_flag_calle_x_vecinos = polyShape.polyIntersects(ps_calles_i, ps_predios_comuna, true)
        ps_predios_comuna_i = polyShape.subShape(ps_predios_comuna, findall(any(mat_flag_calle_x_vecinos, dims=1)[:]))
        ps_calles_i = polyShape.polyDifference(ps_calles_i, ps_predios_comuna_i)

        flag_verde_x_vecinos, mat_flag_verde_x_vecinos = polyShape.polyIntersects(ps_calles_i, ps_areas_verdes, true)
        ps_areas_verdes_i = polyShape.subShape(ps_areas_verdes, findall(any(mat_flag_verde_x_vecinos, dims=1)[:]))
        ps_calles_i = polyShape.polyDifference(ps_calles_i, ps_areas_verdes_i)

        df_segmentos_combi = filter(r -> r.id_segmento_calle in vec_segmento_calle, df_semento_calle)
        ls_segmentos_combi = wkt4326_to_local(df_segmentos_combi[:, "geom_wkt"], dx, dy)

        for j = 1:ps_calles_i.NumRegions
            ps_calles_j = polyShape.subShape(ps_calles_i, j)

            flag_intersects, mat_intersects = polyShape.polyIntersects(ps_calles_j, ls_segmentos_combi, true)
            intersecting_indices = findall(any(mat_intersects, dims=1)[:])

            if !isempty(intersecting_indices)
                intersecting_segments = df_segmentos_combi[intersecting_indices, "id_segmento_calle"]
                intersecting_segment_names = df_segmentos_combi[intersecting_indices, "nombre_calle"]
                segmento_calle_intersecting = "[" * join(intersecting_segments, ", ") * "]"
                nombre_calle_intersecting = "[" * join(unique(intersecting_segment_names), ", ") * "]"
            else
                segmento_calle_intersecting = "[]"
                nombre_calle_intersecting = "[]"
            end

            ps_calles_4326_j, ps_calles_32719_j = local_to_4326(ps_calles_j, dx, dy)

            push!(data_calles_combis, (
                id_calle_combi = id_combi * "_" * string(j),
                id_combi = id_combi,
                lista_segmento_calle = segmento_calle_intersecting,
                lista_nombre_calle = nombre_calle_intersecting,
                calles_4326_wkt = polyShape.polyshape2wkt(ps_calles_4326_j),
                calles_32719_wkt = polyShape.polyshape2wkt(ps_calles_32719_j)
            ))
        end
    catch e
        println("[$(comuna)] Error processing combi $(i)/$(nrow(df_combis)): $(row.id_combi) - $e")
    end
end
df_calles_combis = DataFrame(data_calles_combis)
println("[$(comuna)] Calles combis complete: $(nrow(df_calles_combis)) records")


# ─── GENERA RELACIONES COMBI-CALLE ───────────────────────────────────────────

df_segmento_calle_to_calles_combi = DataFrame(id_calle_combi=String[], id_segmento_calle=String[])
for row in eachrow(df_calles_combis)
    segmentos_str = replace(replace(row.lista_segmento_calle, "[" => ""), "]" => "")
    if segmentos_str != ""
        segmentos = strip.(split(segmentos_str, ","))
        for segmento in segmentos
            if segmento != ""
                push!(df_segmento_calle_to_calles_combi, (id_calle_combi=row.id_calle_combi, id_segmento_calle=segmento))
            end
        end
    end
end

df_combi_to_calles_combi = nrow(df_calles_combis) > 0 ? unique(df_calles_combis[:, ["id_combi", "id_calle_combi"]]) : DataFrame(id_combi=String[], id_calle_combi=String[])


# ─── GENERA df_calles_contexto_combis ────────────────────────────────────────

data_calles_contexto_combis = []
for (i, row) in enumerate(eachrow(df_combis))
    println("[$(comuna)] Procesando Calles Contexto Combi $(i)/$(nrow(df_combis)): $(row.id_combi)")
    ps_combi_i = dict_combis_local[row.id_combi]
    ps_combi_buffer_i = polyGdal.shapeBuffer(ps_combi_i, 70.0, 30)
    ps_segmentos_buffer_i = polyShape.polyIntersection(ps_combi_buffer_i, ps_segmentos)
    ps_verdes_buffer_i = polyShape.polyIntersection(ps_combi_buffer_i, ps_areas_verdes)
    ps_predios_buffer_i = polyShape.polyIntersection(ps_combi_buffer_i, ps_predios_comuna)

    ps_calles_contexto_i = polyShape.polyDifference(ps_segmentos_buffer_i, ps_verdes_buffer_i)
    ps_calles_contexto_i = polyShape.polyDifference(ps_calles_contexto_i, ps_predios_buffer_i)
    ps_calles_contexto_i = polyShape.polySimplify(ps_calles_contexto_i, 2)

    ps_calles_contexto_4326_i, _ = local_to_4326(ps_calles_contexto_i, dx, dy)

    push!(data_calles_contexto_combis, (
        id_combi = row.id_combi,
        calles_contexto_4326_wkt = polyShape.polyshape2wkt(ps_calles_contexto_4326_i)
    ))
end
df_calles_contexto_combis = DataFrame(data_calles_contexto_combis)
println("[$(comuna)] Calles contexto complete: $(nrow(df_calles_contexto_combis)) records")


# ─── ACCUMULATE RESULTS ─────────────────────────────────────────────────────

append!(all_calles_predios, data_calles_predios)
append!(all_predio_to_calles_predio, [(codigo_predial=r.codigo_predial, id_calle_predio=r.id_calle_predio) for r in eachrow(df_predio_to_calles_predio)])
append!(all_segmento_calle_to_calles_predio, [(id_calle_predio=r.id_calle_predio, id_segmento_calle=r.id_segmento_calle) for r in eachrow(df_segmento_calle_to_calles_predio)])
append!(all_calles_combis, data_calles_combis)
append!(all_segmento_calle_to_calles_combi, [(id_calle_combi=r.id_calle_combi, id_segmento_calle=r.id_segmento_calle) for r in eachrow(df_segmento_calle_to_calles_combi)])
append!(all_combi_to_calles_combi, [(id_combi=r.id_combi, id_calle_combi=r.id_calle_combi) for r in eachrow(df_combi_to_calles_combi)])
append!(all_calles_contexto_combis, data_calles_contexto_combis)

println("[$(comuna)] Comuna complete!")
println("")

end


# ═══════════════════════════════════════════════════════════════════════════════
# EXPORTA DATOS A LA NUBE
# ═══════════════════════════════════════════════════════════════════════════════
println("Building final DataFrames...")
df_calles_predios = DataFrame(all_calles_predios)
df_predio_to_calles_predio = DataFrame(all_predio_to_calles_predio)
df_segmento_calle_to_calles_predio = DataFrame(all_segmento_calle_to_calles_predio)
df_calles_combis = DataFrame(all_calles_combis)
df_segmento_calle_to_calles_combi = DataFrame(all_segmento_calle_to_calles_combi)
df_combi_to_calles_combi = DataFrame(all_combi_to_calles_combi)
df_calles_contexto_combis = DataFrame(all_calles_contexto_combis)

println("Uploading to S3...")
upload_and_cleanup(df_calles_predios, "calles_predios.csv", conn_aws, aws_bucket)
upload_and_cleanup(df_predio_to_calles_predio, "rel_predio_to_calles_predio.csv", conn_aws, aws_bucket)
upload_and_cleanup(df_segmento_calle_to_calles_predio, "rel_segmento_calle_to_calles_predio.csv", conn_aws, aws_bucket)
upload_and_cleanup(df_calles_combis, "calles_combis.csv", conn_aws, aws_bucket)
upload_and_cleanup(df_calles_contexto_combis, "calles_contexto_combis.csv", conn_aws, aws_bucket)
upload_and_cleanup(df_combi_to_calles_combi, "rel_combi_to_calles_combi.csv", conn_aws, aws_bucket)
upload_and_cleanup(df_segmento_calle_to_calles_combi, "rel_segmento_calle_to_calles_combi.csv", conn_aws, aws_bucket)

if isfile("box_calle_predio.csv")
    rm("box_calle_predio.csv")
    println("box_calle_predio.csv erased.")
end

println("All comunas processed successfully!")
