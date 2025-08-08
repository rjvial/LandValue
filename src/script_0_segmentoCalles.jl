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

###############################################################################


comuna = "vitacura"
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


query = """
MATCH (p:Predio)-[:TIENE_GEOM]->(gp:Geom_Predio)
WHERE p.comuna = '$(comuna)'
RETURN p.codigo_predial AS codigo_predial,
gp.geom_wkt AS geom_wkt
"""
df_predios = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)

# Create results array to store intersections
intersections = []

# Convert street segments to polyshapes once
println("Converting street segments to polyshapes...")
ps_segmentos = polyShape.astext2polyshape(df_semento_calle[:, "geom_wkt"])
ps_segmentos = polyShape.setPolyOrientation(ps_segmentos, 1)
ps_segmentos = polyShape.reproject_polyshape(ps_segmentos)

# Loop over all predios
# i=1; row = eachrow(df_predios)[i]
for (i, row) in enumerate(eachrow(df_predios))
    println("Processing predio $(i)/$(nrow(df_predios)): $(row.codigo_predial)")
    
    predio_wkt = row.geom_wkt
    codigo_predial = row.codigo_predial
    
    try
        # Convert predio to polyshape
        ps_predio = polyShape.astext2polyshape([predio_wkt])
        ps_predio = polyShape.setPolyOrientation(ps_predio, 1)
        ps_predio = polyShape.reproject_polyshape(ps_predio)
        
        # Create 30-meter buffer around predio
        ps_buffer = polyShape.shapeBuffer(ps_predio, 30.0, 30)
        
        # Check intersection with each street segment
        # j=1; seg_row = eachrow(df_semento_calle)[j]
        for (j, seg_row) in enumerate(eachrow(df_semento_calle))
            seg_id = seg_row.id_segmento_calle
            
            try
                # Check if buffer intersects with street segment
                intersection = polyShape.polyIntersect(ps_buffer, polyShape.subShape(ps_segmentos, j))
                
                # If intersection exists and has vertices
                if !isempty(intersection.Vertices) && length(intersection.Vertices[1]) > 0
                    push!(intersections, (
                        codigo_predial = codigo_predial,
                        id_segmento_calle = seg_id,
                        codigo_calle = seg_row.codigo_calle,
                        nombre_calle = seg_row.nombre_calle,
                        tipo_calle = seg_row.tipo_calle
                    ))
                end
            catch e
                println("Error processing intersection for predio $(codigo_predial) and segment $(seg_id): $(e)")
            end
        end
    catch e
        println("Error processing predio $(codigo_predial): $(e)")
    end
end

# Convert results to DataFrame
df_intersections = DataFrame(intersections)

println("Found $(nrow(df_intersections)) intersections between predios and street segments")
println("Sample results:")
if nrow(df_intersections) > 0
    println(first(df_intersections, min(5, nrow(df_intersections))))
else
    println("No intersections found")
end
