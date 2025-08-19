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

comuna = "vitacura" 

###############################################################################

# AND n.id_segmento_calle IN ["305917", "305918", "305920", "305624", "305956", "305960", "305729"]
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
ps_segmentos = polyGdal.astext2shape(df_semento_calle[:, "geom_wkt"])
ps_segmentos = polyShape.shape_4326to32719(ps_segmentos)
ps_segmentos, dx, dy = polyShape.ajustaCoordenadas(ps_segmentos)


# # 13132041005026_10
# sup_combi_sii_min = 800;    sup_combi_sii_max = 4000
# length_min_combi = 38;      length_max_combi = 120
# width_min_combi = 20;       width_max_combi = 65
# length_to_width_min = 1;    length_to_width_max = 5.0
# rectangularity_min = 0.95;  rectangularity_max = 1
# convexity_min = 0.95;       convexity_max = 1
# num_predios_min = 1;        num_predios_max = 12


# query = """
# MATCH (c:Combi)
# WHERE 
# // c.length >= $length_min_combi             AND c.length <= $length_max_combi
# // AND c.width >= $width_min_combi                 AND c.width <= $width_max_combi
# // AND c.length_to_width >= $length_to_width_min   AND c.length_to_width <= $length_to_width_max
# // AND c.sup_combi_sii >= $sup_combi_sii_min       AND c.sup_combi_sii <= $sup_combi_sii_max
# // AND c.num_predios >= $num_predios_min           AND c.num_predios <= $num_predios_max
# c.rectangularity >= $rectangularity_min     AND c.rectangularity <= $rectangularity_max
# AND c.convexity >= $convexity_min               AND c.convexity <= $convexity_max
# RETURN DISTINCT  c.manzent AS manzent, c.id_combi AS id_combi, c.predios AS list_predios, 
# c.rectangularity AS rectangularity, c.convexity AS convexity, c.length AS length, c.width AS width,
# c.geom_combi AS geom_wkt
# ORDER BY manzent, id_combi
# """
# df_combis = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)


# # query = """
# #   MATCH (m:Manzana)-[:SE_UBICA_EN_MANZANA]-(p:Predio)-[:TIENE_GEOM]->(gp:Geom_Predio)
# #   WHERE p.comuna = 'vitacura'
# #   RETURN p.codigo_predial AS codigo_predial, m.manzent AS manzent, gp.geom_wkt AS geom_wkt
# # """
# # df_predios = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
# # lista_manzanas = unique(df_predios[:,"manzent"])


# # query = """
# #   MATCH (m:Manzana)-[:SE_UBICA_EN_MANZANA]-(p:Predio)
# #   WHERE p.comuna = 'vitacura'
# #   WITH m
# #   OPTIONAL MATCH (m)-[:ES_VECINA_A]-(m1:Manzana)
# #   RETURN m.manzent AS manzent, apoc.text.join(collect(DISTINCT m1.manzent), ',') AS vecinas
# # """
# # df_manzanas_vecinas = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)


# # # Create results array to store intersections
# intersections = []
# # vec_predios_union = PolyShape[]
# # for m in eachindex(lista_manzanas)
# #     println("Processing manzana $(m)/$(length(lista_manzanas))")    
# #     df_predios_m = df_predios[df_predios[!,"manzent"] .== lista_manzanas[m], "geom_wkt"]
# #     ps_predios_m = polyGdal.astext2shape(df_predios_m)
# #     ps_predios_m = polyShape.shape_4326to32719(ps_predios_m)
# #     ps_predios_m = polyShape.ajustaCoordenadas(ps_predios_m, dx, dy)
# #     ps_predios_m = polyShape.setPolyOrientation(ps_predios_m, 1)

# #     push!(vec_predios_union, polyShape.polyUnion(ps_predios_m))
# # end


# # i=1; row = eachrow(df_combis)[i]
# for (i, row) in enumerate(eachrow(df_combis))
#     println("Processing combi $(i)/$(nrow(df_combis)): $(row.id_combi)")
    
#     combi_wkt = row.geom_wkt
#     id_combi = row.id_combi

#     # Convert combi to polyshape
#     ps_combi_i = polyGdal.astext2shape([combi_wkt])
#     ps_combi_i = polyShape.shape_4326to32719(ps_combi_i)
#     ps_combi_i = polyShape.ajustaCoordenadas(ps_combi_i, dx, dy)
#     ps_combi_i = polyShape.setPolyOrientation(ps_combi_i, 1)
#     ps_hull_i = polyShape.setPolyOrientation(polyShape.polySimplify(ps_combi_i, 1), 1)
#     side_hull_i = size(ps_hull_i.Vertices[1], 1)

#     # manzent_i = df_combis[df_combis[!,"id_combi"] .== id_combi, "manzent"][1]
#     # df_predios_manzana_i = df_predios[df_predios[!,"manzent"] .== manzent_i, "geom_wkt"]
#     # ps_predios_manzana_i = polyGdal.astext2shape(df_predios_manzana_i)
#     # ps_predios_manzana_i = polyShape.shape_4326to32719(ps_predios_manzana_i)
#     # ps_predios_manzana_i = polyShape.ajustaCoordenadas(ps_predios_manzana_i, dx, dy)
#     # ps_predios_manzana_i = polyShape.setPolyOrientation(ps_predios_manzana_i, 1)


#     for edge = 1:side_hull_i
#         box_i_edge = polyShape.polyBoxFromEdge(ps_hull_i, edge, 30)
#         box_i_edge = polyShape.rotate_to_first_ccw(box_i_edge, box_i_edge.Vertices[1][1,:])

#         # Check intersection with each street segment
#         # j=1; seg_row = eachrow(df_semento_calle)[j]
#         for (j, seg_row) in enumerate(eachrow(df_semento_calle))
#             seg_id = seg_row.id_segmento_calle
            
#             # Check if buffer intersects with street segment
#             ps_segmento_j = polyShape.subShape(ps_segmentos, j)
#             ps_intersection = polyGdal.shapeIntersect(box_i_edge, ps_segmento_j)
#             length_interseccion = polyShape.lineLength(ps_intersection)
#             # Handle both scalar and vector results from lineLength
#             total_length = isa(length_interseccion, Vector) ? sum(length_interseccion) : length_interseccion
#             # If intersection exists and has vertices
#             if total_length >= 1 && !isempty(ps_intersection.Vertices) 
#                 # box_i_edge_x_predios = polyShape.polyArea(polyShape.polyIntersect(box_i_edge, ps_predios_manzana_i))

#                 # if box_i_edge_x_predios < 0.5
                    
#                     # manzanas_vecinas_i_edge = df_manzanas_vecinas[df_manzanas_vecinas[:, "manzent"] .== manzent_i, "vecinas"]
#                     # manzanas_vecinas_i_edge = parse.(Int, split(manzanas_vecinas_i_edge[1], ","))

#                     # df_manzana_vecinas_i_edge = df_predios[in.(df_predios[!,"manzent"], Ref(manzanas_vecinas_i_edge)), "geom_wkt"]
#                     # ps_manzana_vecinas_i_edge = polyGdal.astext2shape(df_manzana_vecinas_i_edge)
#                     # ps_manzana_vecinas_i_edge = polyShape.shape_4326to32719(ps_manzana_vecinas_i_edge)
#                     # ps_manzana_vecinas_i_edge = polyShape.ajustaCoordenadas(ps_manzana_vecinas_i_edge, dx, dy)
#                     # ps_manzana_vecinas_i_edge = polyShape.setPolyOrientation(ps_manzana_vecinas_i_edge, 1)

#                     # box_i_edge = polyShape.polyDifference(box_i_edge, ps_manzana_vecinas_i_edge)
#                     box_i_edge = polyShape.ajustaCoordenadasInversa(box_i_edge, dx, dy)
#                     box_i_edge = polyShape.shape_32719to4326(box_i_edge)

#                     push!(intersections, (
#                         id_combi = id_combi,
#                         id_segmento_calle = seg_id,
#                         codigo_calle = seg_row.codigo_calle,
#                         nombre_calle = seg_row.nombre_calle,
#                         tipo_calle = seg_row.tipo_calle,
#                         geom_wkt = polyShape.polyshape2wkt(box_i_edge),
#                         edge = "[$(box_i_edge.Vertices[1][1,1]), $(box_i_edge.Vertices[1][1,2])]"
#                     ))
#                 # end
#             end
#         end
#     end
    
#     # Save checkpoint every 50 iterations
#     if i % 50 == 0 && !isempty(intersections)
#         println("Saving checkpoint at iteration $(i)...")
#         df_checkpoint = DataFrame(intersections)
#         CSV.write("calles_por_combi.csv", df_checkpoint)
#         println("Checkpoint saved with $(nrow(df_checkpoint)) records")
#     end
# end

# # Convert results to DataFrame
# df_intersections = DataFrame(intersections)
# df_intersections = unique(df_intersections)
# CSV.write("calles_por_combi.csv", df_intersections)


################################################################################################
################################################################################################

# 13132011001009_107 13132011001009_40 13132011001012_110
df_calles = CSV.read("calles_por_combi.csv", DataFrame)

ps_calles_combi = df_calles[df_calles[!, "id_combi"] .== "13132011001004_14", "geom_wkt"]

ps_calles_combi = polyGdal.astext2shape(ps_calles_combi)
ps_calles_combi = polyShape.setPolyOrientation(ps_calles_combi, 1)
ps_calles_combi = polyShape.shape_4326to32719(ps_calles_combi)
ps_calles_combi = polyShape.ajustaCoordenadas(ps_calles_combi, dx, dy)


query = """
MATCH (p:Predio)-[:CONFORMA_COMBI]->(c:Combi)
WHERE p.comuna = '$(comuna)' AND c.id_combi = '13132011001004_14'
RETURN DISTINCT c.id_combi AS id_combi, c.geom_combi AS geom_wkt
"""
df_combi = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
ps_combi = polyGdal.astext2shape(df_combi[!, "geom_wkt"])
ps_combi = polyShape.setPolyOrientation(ps_combi, 1)
ps_combi = polyShape.shape_4326to32719(ps_combi)

ps_combi = polyShape.setPolyOrientation(ps_combi, 1)
ps_combi = polyShape.ajustaCoordenadas(ps_combi, dx, dy)

# function refina_segmentos_calle_combi(ps_combi, ps_calles_combi, i)
num_segmentos = ps_calles_combi.NumRegions
vec_ps_aux = [polyShape.subShape(ps_calles_combi, i) for i = 1:num_segmentos]

ps_calles = PolyShape([], 0)
for i = 1:num_segmentos
    if i == 1
        ps_calles = vec_ps_aux[i]
    else
        ps_calles = polyClipper.polyOffset(polyShape.polyUnion(polyClipper.polyOffset(ps_calles, 0.1), polyClipper.polyOffset(vec_ps_aux[i], 0.1)), -0.1)
    end
end

for i = 1:num_segmentos
    i_prev = mod1(i - 1, num_segmentos)
    
    ps_i_prev = polyShape.subShape(ps_calles_combi, i_prev)
    ps_i = polyShape.subShape(ps_calles_combi, i)
    start_pt = ps_i.Vertices[1][1,:]

    ps_inter_i_prev = polyShape.polyIntersect(ps_i, ps_i_prev)
    if isempty(ps_inter_i_prev.Vertices) 
        ps_i_ext = polyShape.partialPolyOffset(ps_i, [2, 4], 40)
        ps_i_prev_ext = polyShape.partialPolyOffset(ps_i_prev, [2, 4], 40)
        ps_ext_inter = polyShape.polyIntersect(ps_i_ext, ps_i_prev_ext)
        if !isempty(ps_ext_inter.Vertices)
            ps_ext_inter_ = polyShape.polyDifference(ps_ext_inter, polyShape.partialPolyOffset(ps_i, [3, 4], [10, 40]))
            ps_ext_inter_ = polyShape.polyDifference(ps_ext_inter_, polyShape.partialPolyOffset(ps_i_prev, [2, 3], [40, 10]))
            
            if ps_ext_inter_.NumRegions >= 1
                ps_ext_inter = deepcopy(ps_ext_inter_)
            end

            ps_i_aux = polyShape.convHull(PolyShape([[ps_ext_inter.Vertices[1]; ps_i.Vertices[1]]],1))
            ps_i_prev_aux = polyShape.convHull(PolyShape([[ps_ext_inter.Vertices[1]; ps_i_prev.Vertices[1]]],1))
            ps_x = polyShape.polyUnion(ps_i_aux, ps_i_prev_aux)
            ps_ext_inter = polyShape.polyDifference(polyShape.polyDifference(ps_x, ps_i), ps_i_prev)

            ps_delta_i_prev, ps_delta_i = polyShape.dividePoly(ps_ext_inter, ps_i.Vertices[1][2,:])
        # ----> Revisar dividePoly: hay casos en que ps_delta_i_prev, ps_delta_i y otros en que ps_delta_i, ps_delta_i_prev

            vec_ps_aux[i] = polyShape.polySimplify(polyShape.polyDifference(polyShape.polyUnion(polyShape.partialPolyOffset(vec_ps_aux[i],[2],.1), ps_delta_i), ps_combi))
            vec_ps_aux[i_prev] = polyShape.polySimplify(polyShape.polyDifference(polyShape.polyUnion(polyShape.partialPolyOffset(vec_ps_aux[i_prev],[4],.1), ps_delta_i_prev), ps_combi))
        else
            vec_ps_aux[i] = polyShape.polySimplify(polyShape.polyDifference(vec_ps_aux[i], ps_combi))
            vec_ps_aux[i_prev] = polyShape.polySimplify(polyShape.polyDifference(vec_ps_aux[i_prev], ps_combi))
        end
    else
        ps_delta_i_prev, ps_delta_i = polyShape.dividePoly(ps_inter_i_prev, ps_i.Vertices[1][1,:])

        vec_ps_aux[i] = polyShape.polySimplify(polyShape.polyUnion(polyShape.polyDifference(vec_ps_aux[i], ps_inter_i_prev), ps_delta_i))
        vec_ps_aux[i_prev] = polyShape.polySimplify(polyShape.polyUnion(polyShape.polyDifference(vec_ps_aux[i_prev], ps_inter_i_prev), ps_delta_i_prev))
        
    end
end

    # return vec_ps_aux
# end

# vec_ps_aux = refina_segmentos_calle_combi(ps_combi, ps_calles_combi, 2)
