# ═══════════════════════════════════════════════════════════════════════════════
# DATABASE CONNECTION & AWS INFRASTRUCTURE SETUP
# ═══════════════════════════════════════════════════════════════════════════════
# Establishes secure connections to AWS services and Neo4j graph database
# running on EC2 instance for street and building data extraction
using LandValue, DotEnv, DataFrames, CSV

my_env = DotEnv.config("secrets.env")
conn_aws = aws_julia.connection(my_env["AWS_ACCESS_KEY"], my_env["AWS_SECRET_KEY"], my_env["AWS_REGION"])

instance_info = aws_julia.find_instance_by_name("Neo4j-EC2", conn_aws)

# ── SSH + Remote cypher-shell (no local cypher-shell needed) ─────────────────
key_pair   = "neo4j-key-pair.pem"
ec2_user   = "ec2-user"
public_dns = instance_info["dnsName"]

folder = "/usr/bin/cypher-shell"
neo4j_host = "bolt://localhost:7687"
neo4j_user = "neo4j"
neo4j_password = "x67y1332"

conn_neo4j = neo4j_julia.connection(neo4j_host, neo4j_user, neo4j_password, folder, key_pair, ec2_user, public_dns)

# ───────────────────────────────────────────────────────────────────────────────
# STREET SEGMENTS EXTRACTION FROM GRAPH DATABASE
# ───────────────────────────────────────────────────────────────────────────────
# Queries Neo4j for all street segments in target commune, transforms coordinates
# from WGS84 (4326) to UTM Zone 19S (32719) and adjusts for local processing
comuna = "vitacura" 

# AND n.id_segmento_calle IN ["305811", "309105"]
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
ls_segmentos = polyGdal.astext2shape(df_semento_calle[:, "geom_wkt"])
ls_segmentos = polyShape.shape_4326to32719(ls_segmentos)
ls_segmentos, dx, dy = polyShape.ajustaCoordenadas(ls_segmentos)
ps_segmentos = polyShape.lines2Polygons(ls_segmentos, 45)


# ───────────────────────────────────────────────────────────────────────────────
# GEOMETRIC FILTERING CRITERIA FOR COMBI 
# ───────────────────────────────────────────────────────────────────────────────
# Defines dimensional and shape quality thresholds for valid building combinations
# based on urban planning standards and development feasibility constraints
sup_combi_sii_min = 800;    sup_combi_sii_max = 4000
length_min_combi = 38;      length_max_combi = 120
width_min_combi = 20;       width_max_combi = 65
length_to_width_min = 1;    length_to_width_max = 5.0
rectangularity_min = 0.95;  rectangularity_max = 1
convexity_min = 0.95;       convexity_max = 1
num_predios_min = 1;        num_predios_max = 12


#c.id_combi = '13132011001012_31' AND
query = """
MATCH (c:Combi) 
WHERE 
c.length >= $length_min_combi             AND c.length <= $length_max_combi
AND c.width >= $width_min_combi                 AND c.width <= $width_max_combi
AND c.length_to_width >= $length_to_width_min   AND c.length_to_width <= $length_to_width_max
AND c.rectangularity >= $rectangularity_min     AND c.rectangularity <= $rectangularity_max
AND c.convexity >= $convexity_min               AND c.convexity <= $convexity_max
// AND c.sup_combi_sii >= $sup_combi_sii_min       AND c.sup_combi_sii <= $sup_combi_sii_max
// AND c.num_predios >= $num_predios_min           AND c.num_predios <= $num_predios_max
RETURN DISTINCT  c.manzent AS manzent, c.id_combi AS id_combi, c.predios AS list_predios, 
c.rectangularity AS rectangularity, c.convexity AS convexity, c.length AS length, c.width AS width,
c.geom_combi AS geom_wkt
ORDER BY manzent, id_combi
"""
df_combis = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)


# ═══════════════════════════════════════════════════════════════════════════════
# GENERA BOXES PARA CADA SEGMENTO DE CALLE 
# ═══════════════════════════════════════════════════════════════════════════════
# For each building combination edge, creates rectangular buffers using polyBoxFromEdge
# to detect which street segments are adjacent. Only processes edges not blocked by
# private properties, generating precise frontage boxes that touch street infrastructure.

const BOX_HEIGHT = 30  # Height of street frontage boxes in meters

query = """
    MATCH (m:Manzana)<-[:SE_UBICA_EN_MANZANA]-(p:Predio)-[:TIENE_GEOM]->(gp:Geom_Predio)
    WHERE p.comuna = 'vitacura'
    RETURN p.codigo_predial AS codigo_predial, m.manzent AS manzent, gp.geom_wkt AS geom_wkt
"""
df_predios = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
# lista_manzanas = unique(df_predios[:,"manzent"])


# Create results array to store vec_box_calle_combi
vec_box_calle_combi = []
# 13132011002005_19
# i=1; row = eachrow(df_combis)[i]

for (i, row) in enumerate(eachrow(df_combis))
    println("Processing combi $(i)/$(nrow(df_combis)): $(row.id_combi)")
    
    combi_wkt = row.geom_wkt
    id_combi = row.id_combi

    # Convert combi to polyshape
    ps_combi_i = polyGdal.astext2shape(combi_wkt)
    ps_combi_i = polyShape.shape_4326to32719(ps_combi_i)
    ps_combi_i = polyShape.ajustaCoordenadas(ps_combi_i, dx, dy)
    ps_combi_i = polyShape.setPolyOrientation(ps_combi_i, 1)
    ps_hull_i = polyShape.setPolyOrientation(polyShape.polySimplify(ps_combi_i, 1), 1)
    num_sides_hull_i = size(ps_hull_i.Vertices[1], 1)

    manzent_i = df_combis[df_combis[!,"id_combi"] .== id_combi, "manzent"][1]
    df_predios_manzana_i = df_predios[df_predios[!,"manzent"] .== manzent_i, "geom_wkt"]
    ps_predios_manzana_i = polyGdal.astext2shape(df_predios_manzana_i)
    ps_predios_manzana_i = polyShape.shape_4326to32719(ps_predios_manzana_i)
    ps_predios_manzana_i = polyShape.ajustaCoordenadas(ps_predios_manzana_i, dx, dy)
    ps_predios_manzana_i = polyShape.polyUnion(polyShape.setPolyOrientation(ps_predios_manzana_i, 1))

    for edge = 1:num_sides_hull_i

        if polyShape.polyArea(polyShape.polyIntersection(polyShape.polyBoxFromEdge(ps_hull_i, edge, 5), ps_predios_manzana_i)) <= 3
            box_i_edge = polyShape.polyBoxFromEdge(ps_hull_i, edge, BOX_HEIGHT)
            box_i_edge = polyShape.rotate_to_first_ccw(box_i_edge, box_i_edge.Vertices[1][1,:])
            # Check intersection with each street segment
            # j=1; seg_row = eachrow(df_semento_calle)[j]
            for (j, seg_row) in enumerate(eachrow(df_semento_calle))
                seg_id = seg_row.id_segmento_calle
                
                # Check if buffer intersects with street segment
                ls_segmento_j = polyShape.subShape(ls_segmentos, j)

                flag_touches = polyGdal.shapeTouches(polyShape.partialPolyOffset(box_i_edge,[1],5), ls_segmento_j)
                # If intersection exists and has vertices
                if flag_touches 
                    box_i_edge = polyShape.ajustaCoordenadasInversa(box_i_edge, dx, dy)
                    box_i_edge = polyShape.shape_32719to4326(box_i_edge)

                    push!(vec_box_calle_combi, (
                        id_combi = id_combi,
                        id_segmento_calle = seg_id,
                        codigo_calle = seg_row.codigo_calle,
                        nombre_calle = seg_row.nombre_calle,
                        tipo_calle = seg_row.tipo_calle,
                        id_edge = edge,
                        num_edges = num_sides_hull_i,
                        edge = "[$(box_i_edge.Vertices[1][1,1]), $(box_i_edge.Vertices[1][1,2])]",
                        geom_wkt = polyShape.polyshape2wkt(box_i_edge)
                    ))
                end
            end
        end
    end
    
    # Save checkpoint every 50 iterations
    if i % 50 == 0 && !isempty(vec_box_calle_combi)
        println("Saving checkpoint at iteration $(i)...")
        df_checkpoint = DataFrame(vec_box_calle_combi)
        CSV.write("box_calle_combi.csv", df_checkpoint)
        println("Checkpoint saved with $(nrow(df_checkpoint)) records")
    end
end

# Convert results to DataFrame
df_box_calle_combi = DataFrame(vec_box_calle_combi)
df_box_calle_combi = unique(df_box_calle_combi)
CSV.write("box_calle_combi.csv", df_box_calle_combi)


# ───────────────────────────────────────────────────────────────────────────────
# OBTIENE GEOM DE PREDIOS EN LA COMUNA 
# ───────────────────────────────────────────────────────────────────────────────
# Retrieves all property boundaries within commune to identify private land that
# should be excluded from street frontage calculations and public space analysis
display("Obtiene predios y ajusta coordenadas")
query = """
MATCH (gp:Geom_Predio)<-[:TIENE_GEOM]-(p:Predio)
WHERE p.comuna = 'vitacura'
RETURN DISTINCT gp.geom_wkt AS geom_wkt
"""
df_predios_comuna = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
ps_predios_comuna = polyGdal.astext2shape(df_predios_comuna[:, "geom_wkt"])
ps_predios_comuna = polyShape.setPolyOrientation(ps_predios_comuna,1)
ps_predios_comuna = polyShape.shape_4326to32719(ps_predios_comuna)
ps_predios_comuna = polyShape.ajustaCoordenadas(ps_predios_comuna, dx, dy)


# ───────────────────────────────────────────────────────────────────────────────
# OBTIENE GEOM AREAS VERDES
# ───────────────────────────────────────────────────────────────────────────────
# Extracts parks, gardens, and green spaces from POI database to distinguish
# between street areas and landscaped public spaces in frontage calculations
display("Obtiene areas verdes contenidos en el buffer del predio y ajusta coordenadas")
query = """
MATCH (cat:Poi_Category)<-[:ES_POI_TIPO]-(poi:Poi)
WHERE cat.poi_category in ['park', 'garden'] AND poi.comuna = 'vitacura'
RETURN poi.geom_wkt AS geom_wkt
"""
df_areas_verdes = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
ps_areas_verdes = polyGdal.astext2shape(df_areas_verdes[:, "geom_wkt"])
ps_areas_verdes = polyShape.setPolyOrientation(ps_areas_verdes, 1)
ps_areas_verdes = polyShape.shape_4326to32719(ps_areas_verdes)
ps_areas_verdes = polyShape.ajustaCoordenadas(ps_areas_verdes, dx, dy)


# ═══════════════════════════════════════════════════════════════════════════════
# GENERA df_calles_combis
# ═══════════════════════════════════════════════════════════════════════════════

function stitch_street_segments_together(id_combi, df_calles, df_combis)
    vec_segmento_calle = unique(df_calles[df_calles[!, "id_combi"] .== id_combi, "id_segmento_calle"])

    df_calles_combi = df_calles[df_calles[!, "id_combi"] .== id_combi, :]
    ps_calles_combi = df_calles[df_calles[!, "id_combi"] .== id_combi, "geom_wkt"]
    ps_calles_combi = polyGdal.astext2shape(ps_calles_combi)
    ps_calles_combi = polyShape.setPolyOrientation(ps_calles_combi, 1)
    ps_calles_combi = polyShape.shape_4326to32719(ps_calles_combi)
    ps_calles_combi = polyShape.ajustaCoordenadas(ps_calles_combi, dx, dy)

    num_segmentos = ps_calles_combi.NumRegions

    ps_combi = polyGdal.astext2shape(df_combis[df_combis[!, "id_combi"] .== id_combi, "geom_wkt"])
    ps_combi = polyShape.setPolyOrientation(ps_combi, 1)
    ps_combi = polyShape.shape_4326to32719(ps_combi)
    ps_combi = polyShape.setPolyOrientation(ps_combi, 1)
    ps_combi = polyShape.ajustaCoordenadas(ps_combi, dx, dy)

    ps_calles = PolyShape([], 0)
    for i = 1:num_segmentos
        i_prev = mod1(i - 1, num_segmentos)

        num_edges = df_calles_combi[i, "num_edges"][1]
        edge_i = df_calles_combi[i, "id_edge"][1]
        edge_i_prev = df_calles_combi[i_prev, "id_edge"][1]

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
    
    list_segmento_calle = "[" * join(vec_segmento_calle, ", ") * "]"

    return ps_calles, ps_combi, list_segmento_calle
end

df_calles = CSV.read("box_calle_combi.csv", DataFrame)

data_calles_combis = []
for (i, row) in enumerate(eachrow(df_combis))
    println("Processing combi $(i)/$(nrow(df_combis)): $(row.id_combi)")

    try
        id_combi = row.id_combi
        ps_calles_i, ps_combi_i, list_segmento_calle = stitch_street_segments_together(id_combi, df_calles, df_combis)

        flag_calle_x_vecinos, mat_flag_calle_x_vecinos = polyShape.polyIntersects(ps_calles_i, ps_predios_comuna, true)
        ps_predios_comuna_i = polyShape.subShape(ps_predios_comuna, findall(any(mat_flag_calle_x_vecinos, dims=1)[:]))
        ps_calles_i = polyShape.polyDifference(ps_calles_i, ps_predios_comuna_i)

        flag_verde_x_vecinos, mat_flag_verde_x_vecinos = polyShape.polyIntersects(ps_calles_i, ps_areas_verdes, true)
        ps_areas_verdes_i = polyShape.subShape(ps_areas_verdes, findall(any(mat_flag_verde_x_vecinos, dims=1)[:]))
        ps_calles_i = polyShape.polyDifference(ps_calles_i, ps_areas_verdes_i)

        vec_segmento_calle = parse.(Int, strip.(split(replace(replace(list_segmento_calle, "[" => ""), "]" => ""), ",")))
        df_segmentos_combi = filter(row -> row.id_segmento_calle in vec_segmento_calle, df_semento_calle)
        ls_segmentos_combi = polyGdal.astext2shape(df_segmentos_combi[:, "geom_wkt"])
        ls_segmentos_combi = polyShape.shape_4326to32719(ls_segmentos_combi)
        ls_segmentos_combi = polyShape.ajustaCoordenadas(ls_segmentos_combi, dx, dy)

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
            
            ps_calles_32719_j = polyShape.ajustaCoordenadasInversa(ps_calles_j, dx, dy)
            ps_calles_4326_j = polyShape.shape_32719to4326(ps_calles_32719_j)

            push!(data_calles_combis, (
                id_calle_combi = id_combi * "_" * string(j),
                id_combi = id_combi,
                lista_segmento_calle = segmento_calle_intersecting,
                lista_nombre_calle = nombre_calle_intersecting,
                calles_4326_wkt = polyShape.polyshape2wkt(ps_calles_4326_j),
                calles_32719_wkt = polyShape.polyshape2wkt(ps_calles_32719_j)
            ))
        end
    catch
        println("Error processing combi $(i)/$(nrow(df_combis)): $(row.id_combi)")
    end
end
df_calles_combis = DataFrame(data_calles_combis)


# ═══════════════════════════════════════════════════════════════════════════════
# GENERA df_segmento_calle_to_calles_combi y df_combi_to_calles_combi
# ═══════════════════════════════════════════════════════════════════════════════
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

df_combi_to_calles_combi = unique(df_calles_combis[:, ["id_combi", "id_calle_combi"]])


# ═══════════════════════════════════════════════════════════════════════════════
# GENERA df_calles_contexto_combis
# ═══════════════════════════════════════════════════════════════════════════════
lista_combis = unique(df_combis[:,"id_combi"])
num_combis = length(lista_combis)
data_calles_contexto_combis = []
for (i, row) in enumerate(eachrow(df_combis))
    println("Procesando Calles Contexto Combi $(i)/$(num_combis)")
    ps_combi_i = polyGdal.astext2shape(row.geom_wkt)
    ps_combi_i = polyShape.shape_4326to32719(ps_combi_i)
    ps_combi_i = polyShape.ajustaCoordenadas(ps_combi_i, dx, dy)
    ps_combi_buffer_i = polyGdal.shapeBuffer(ps_combi_i, 70.0, 30)
    ps_segmentos_buffer_i = polyShape.polyIntersection(ps_combi_buffer_i, ps_segmentos)
    ps_verdes_buffer_i = polyShape.polyIntersection(ps_combi_buffer_i, ps_areas_verdes)
    ps_predios_buffer_i = polyShape.polyIntersection(ps_combi_buffer_i, ps_predios_comuna)

    ps_calles_contexto_i = polyShape.polyDifference(ps_segmentos_buffer_i, ps_verdes_buffer_i)
    ps_calles_contexto_i = polyShape.polyDifference(ps_calles_contexto_i, ps_predios_buffer_i)
    ps_calles_contexto_i = polyShape.polySimplify(ps_calles_contexto_i, 2)

    ps_calles_contexto_32719_i = polyShape.ajustaCoordenadasInversa(ps_calles_contexto_i, dx, dy)
    ps_calles_contexto_4326_i = polyShape.shape_32719to4326(ps_calles_contexto_32719_i)

    push!(data_calles_contexto_combis, (
        id_combi = row.id_combi,
        calles_contexto = ps_calles_contexto_i,
        calles_contexto_4326_wkt = polyShape.polyshape2wkt(ps_calles_contexto_4326_i)
    ))
end
df_calles_contexto_combis = DataFrame(data_calles_contexto_combis)


# ═══════════════════════════════════════════════════════════════════════════════
# EXPORTA DAToS A LA NUBE
# ═══════════════════════════════════════════════════════════════════════════════
aws_bucket = "landengines-data"

local_file_name = "calles_combis.csv"
CSV.write(local_file_name, df_calles_combis)
println("Processing complete. Final data saved to ", local_file_name)
aws_file_name = "kg/$(local_file_name)"
aws_julia.upload_csv_file_to_s3(conn_aws, aws_bucket, aws_file_name, local_file_name)
if isfile(local_file_name)
    rm(local_file_name)
    println("$(local_file_name) Checkpoint file erased.")
end

local_file_name = "calles_contexto_combis.csv"
CSV.write(local_file_name, df_calles_contexto_combis)
println("Processing complete. Final data saved to ", local_file_name)
aws_file_name = "kg/$(local_file_name)"
aws_julia.upload_csv_file_to_s3(conn_aws, aws_bucket, aws_file_name, local_file_name)
if isfile(local_file_name)
    rm(local_file_name)
    println("$(local_file_name) Checkpoint file erased.")
end

local_file_name = "rel_combi_to_calles_combi.csv"
CSV.write(local_file_name, df_combi_to_calles_combi)
println("Processing complete. Final data saved to ", local_file_name)
aws_file_name = "kg/$(local_file_name)"
aws_julia.upload_csv_file_to_s3(conn_aws, aws_bucket, aws_file_name, local_file_name)
if isfile(local_file_name)
    rm(local_file_name)
    println("$(local_file_name) Checkpoint file erased.")
end

local_file_name = "rel_segmento_calle_to_calles_combi.csv"
CSV.write(local_file_name, df_segmento_calle_to_calles_combi)
println("Processing complete. Final data saved to ", local_file_name)
aws_file_name = "kg/$(local_file_name)"
aws_julia.upload_csv_file_to_s3(conn_aws, aws_bucket, aws_file_name, local_file_name)
if isfile(local_file_name)
    rm(local_file_name)
    println("$(local_file_name) Checkpoint file erased.")
end

