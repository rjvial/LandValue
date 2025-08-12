using LandValue, DotEnv, DataFrames, CSV


checkpoint_file = "predios_estrategicos_checkpoint.csv"

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


# # AND n.id_segmento_calle IN ["305918", "305960"]
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
ps_segmentos = polyGdal.astext2lineshape(df_semento_calle[:, "geom_wkt"])
ps_segmentos = polyShape.shape_4326to32719(ps_segmentos)
ps_segmentos, dx, dy = polyShape.ajustaCoordenadas(ps_segmentos)

# # AND p.codigo_predial = '151600010500001'
# query = """
# MATCH (p:Predio)-[:TIENE_GEOM]->(gp:Geom_Predio)
# WHERE p.comuna = '$(comuna)' 
# RETURN p.codigo_predial AS codigo_predial,
# gp.geom_wkt AS geom_wkt
# """
# df_predios = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)

# # Create results array to store intersections
# intersections = []

# # i=1; row = eachrow(df_predios)[i]
# for (i, row) in enumerate(eachrow(df_predios))
#     println("Processing predio $(i)/$(nrow(df_predios)): $(row.codigo_predial)")
    
#     predio_wkt = row.geom_wkt
#     codigo_predial = row.codigo_predial    

#     # Convert predio to polyshape
#     ps_predio_i = polyGdal.astext2polyshape([predio_wkt])
#     ps_predio_i = polyShape.setPolyOrientation(ps_predio_i, 1)
#     ps_predio_i = polyShape.shape_4326to32719(ps_predio_i)

#     ps_predio_i = polyShape.setPolyOrientation(ps_predio_i, 1)
#     ps_predio_i = polyShape.ajustaCoordenadas(ps_predio_i, dx, dy)

#     ps_hull_i = polyShape.setPolyOrientation(polyShape.polySimplify(ps_predio_i, 1), 1)
#     side_hull_i = size(ps_hull_i.Vertices[1], 1)

#     for edge = 1:side_hull_i
#         ps_i_edge = polyShape.polyBoxFromEdge(ps_hull_i, edge, 30)

#         # Check intersection with each street segment
#         # j=1; seg_row = eachrow(df_semento_calle)[j]
#         for (j, seg_row) in enumerate(eachrow(df_semento_calle))
#             seg_id = seg_row.id_segmento_calle
            
#             # Check if buffer intersects with street segment
#             ps_segmento_j = polyShape.subShape(ps_segmentos, j)
#             ps_intersection = polyShape.polyIntersect(ps_i_edge, ps_segmento_j)
#             area_interseccion = polyShape.polyArea(ps_intersection)
#             # If intersection exists and has vertices
#             if area_interseccion >= 10 && !isempty(ps_intersection.Vertices) && length(ps_intersection.Vertices[1]) > 0
#                 ps_i_edge = polyShape.ajustaCoordenadasInversa(ps_i_edge, dx, dy)
#                 ps_i_edge = polyShape.shape_32719to4326(ps_i_edge)

#                 push!(intersections, (
#                     codigo_predial = codigo_predial,
#                     id_segmento_calle = seg_id,
#                     codigo_calle = seg_row.codigo_calle,
#                     nombre_calle = seg_row.nombre_calle,
#                     tipo_calle = seg_row.tipo_calle,
#                     geom_wkt = polyShape.polyshape2wkt(ps_i_edge)
#                 ))
#             end
#         end

#     end
    
#     # Save checkpoint every 50 iterations
#     if i % 50 == 0 && !isempty(intersections)
#         println("Saving checkpoint at iteration $(i)...")
#         df_checkpoint = DataFrame(intersections)
#         CSV.write("calles_por_predio.csv", df_checkpoint)
#         println("Checkpoint saved with $(nrow(df_checkpoint)) records")
#     end
# end

# # Convert results to DataFrame
# df_intersections = DataFrame(intersections)
# df_intersections = unique(df_intersections)
# CSV.write("calles_por_predio.csv", df_intersections)


################################################################################################
################################################################################################


df_calles = CSV.read("calles_por_predio.csv", DataFrame)

ps_calles_predio = df_calles[df_calles[!, "codigo_predial"] .== 151600010500001, "geom_wkt"]

ps_calles_predio = polyGdal.astext2polyshape(ps_calles_predio)
ps_calles_predio = polyShape.setPolyOrientation(ps_calles_predio, 1)
ps_calles_predio = polyShape.shape_4326to32719(ps_calles_predio)
ps_calles_predio = polyShape.ajustaCoordenadas(ps_calles_predio, dx, dy)

# AND p.codigo_predial = '151600010500001'
query = """
MATCH (p:Predio)-[:TIENE_GEOM]->(gp:Geom_Predio)
WHERE p.comuna = '$(comuna)' AND p.codigo_predial = '151600010500001'
RETURN p.codigo_predial AS codigo_predial,
gp.geom_wkt AS geom_wkt
"""
df_predio = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
ps_predio = polyGdal.astext2polyshape(df_predio[!, "geom_wkt"])
ps_predio = polyShape.setPolyOrientation(ps_predio, 1)
ps_predio = polyShape.shape_4326to32719(ps_predio)

ps_predio = polyShape.setPolyOrientation(ps_predio, 1)
ps_predio = polyShape.ajustaCoordenadas(ps_predio, dx, dy)


