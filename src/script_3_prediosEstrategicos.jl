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


num_max_combis = 50 #30
min_rectangularity = 0.92


lista_poi_no_incluir = "['park', 'school', 'bank', 'place_of_worship', 'supermarket', 'sports_centre', 
'fuel', 'clinic', 'garden', 'university', 'courthouse', 'library', 'police', 
'department_store', 'doityourself', 'fire_station', 'college', 'hospital', 'gas', 'cinema', 'shopping_centre', 
'townhall', 'stadium', 'public_building', 'bus_station', 'prison', 'golf_course', 
'monastery']"

query = """
MATCH (p:Predio)-[]-(c:Combi) 
WHERE NOT (p)-[:CONFORMA_ANTEPROYECTO]->(:Anteproyecto) 
AND c.rectangularity >= $(min_rectangularity) 
OPTIONAL MATCH (pc:Poi_Category)-[]-(:Poi)-[:SE_UBICA_EN_PREDIO]->(p) 
WHERE NOT pc.poi_category IN $(lista_poi_no_incluir)
RETURN DISTINCT p.codigo_predial as codigo_predial, p.sup_terreno_sii as sup_terreno_sii 
ORDER BY codigo_predial
"""
df_predios = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)

query_predios_combis = """
MATCH (p:Predio)-[]-(c:Combi) 
WHERE NOT (p)-[:CONFORMA_ANTEPROYECTO]->(:Anteproyecto) 
AND c.rectangularity >= $(min_rectangularity) 
OPTIONAL MATCH (pc:Poi_Category)-[]-(:Poi)-[:SE_UBICA_EN_PREDIO]-(p) 
WHERE NOT pc.poi_category IN $(lista_poi_no_incluir)
RETURN c.manzent as manzent, c.id_combi as id_combi, 
        p.codigo_predial as codigo_predial 
ORDER BY id_combi, codigo_predial
"""
df_predios_combis = neo4j_julia.cypher_to_dataframe(query_predios_combis, conn_neo4j)
unique_manzanas = sort(unique(df_predios_combis.manzent))
num_manzanas = length(unique_manzanas)

# Create a DataFrame to store the results for each manzana.
df_manzanas = DataFrame(manzent = unique_manzanas)
df_manzanas.predios_estrategicos = fill("", length(unique_manzanas))
df_manzanas.num_predios_estrategicos = zeros(Int, length(unique_manzanas))
df_manzanas.tipo_control = fill("sin_control", length(unique_manzanas))
df_manzanas.num_combis_consideradas = fill(0, length(unique_manzanas))
df_manzanas.num_combis_disponibles = fill(0, length(unique_manzanas))
df_manzanas.num_predios_considerados = fill(0, length(unique_manzanas))
df_manzanas.num_predios_disponibles = fill(0, length(unique_manzanas))

# If a checkpoint exists, load it and update df_manzanas accordingly.
if isfile(checkpoint_file)
    println("Checkpoint file found. Resuming from checkpoint...")
    df_checkpoint = CSV.read(checkpoint_file, DataFrame)
    for row in eachrow(df_checkpoint)
        idx = findfirst(==(row.manzent), df_manzanas.manzent)
        if idx !== nothing
            df_manzanas.predios_estrategicos[idx] = coalesce(row.predios_estrategicos, "")
            df_manzanas.num_predios_estrategicos[idx] = row.num_predios_estrategicos
            df_manzanas.tipo_control[idx] = coalesce(row.tipo_control, "sin_control")
            df_manzanas.num_combis_consideradas[idx] = row.num_combis_consideradas
            df_manzanas.num_combis_disponibles[idx] = row.num_combis_disponibles
            df_manzanas.num_predios_considerados[idx] = row.num_predios_considerados
            df_manzanas.num_predios_disponibles[idx] = row.num_predios_disponibles
        end
    end
end

# Loop over each manzana
for i_m in eachindex(unique_manzanas)
    # Skip manzanas that have been processed (i.e. their 'predios_estrategicos' is not empty)
    if df_manzanas.predios_estrategicos[i_m] != ""
        continue
    end

    df_predios_combis_m = df_predios_combis[df_predios_combis.manzent .== unique_manzanas[i_m], :]
    unique_combis_m = unique(df_predios_combis_m.id_combi)
    num_combis_bruto = length(unique_combis_m)
    unique_codigo_predial_m = unique(df_predios_combis_m.codigo_predial)
    num_codigo_predial_bruto = length(unique_codigo_predial_m)

    first_N_combis = unique_combis_m[1:min(num_max_combis, num_combis_bruto)]
    df_predios_combis_m = filter(row -> row.id_combi in first_N_combis, df_predios_combis_m)
    unique_combis_m = unique(df_predios_combis_m.id_combi)

    unique_codigo_predial_m = unique(df_predios_combis_m.codigo_predial)
    num_codigo_predial_m = length(unique_codigo_predial_m)
    df_predios_m = filter(row -> row.codigo_predial in unique_codigo_predial_m, df_predios)
    num_combis_m = length(unique_combis_m)

    display("$(i_m)/$(num_manzanas) Trabajando en Manzana $(unique_manzanas[i_m]). Num Combis: $(num_combis_m)/$(num_combis_bruto). Num Predios: $(num_codigo_predial_m)/$(num_codigo_predial_bruto)")
    C_m = zeros(Int, num_combis_m, num_codigo_predial_m)
    for i_c in 1:num_combis_m, i_p in 1:num_codigo_predial_m
        if any((df_predios_combis_m.id_combi .== unique_combis_m[i_c]) .&& 
               (df_predios_combis_m.codigo_predial .== unique_codigo_predial_m[i_p]))
            C_m[i_c, i_p] = 1
        end
    end

    x_opt = optimal_lot_selection(C_m, df_predios_m; tipo_opt="con_control")
    if sum(x_opt) > 1 || sum(x_opt) == 0
        x_opt = optimal_lot_selection(C_m, df_predios_m; tipo_opt="sin_control")
    else
        df_manzanas.tipo_control[i_m] = "con_control"
    end

    predios_opt = string(unique_codigo_predial_m[x_opt .== 1])
    num_predios_opt = sum(x_opt)
    df_manzanas.predios_estrategicos[i_m] = predios_opt
    df_manzanas.num_predios_estrategicos[i_m] = num_predios_opt

    df_manzanas.num_combis_consideradas[i_m] = num_combis_m
    df_manzanas.num_combis_disponibles[i_m] = num_combis_bruto
    df_manzanas.num_predios_considerados[i_m] = num_codigo_predial_m
    df_manzanas.num_predios_disponibles[i_m] = num_codigo_predial_bruto

    # Save checkpoint every 10 iterations.
    if mod(i_m, 50) == 0
        println("Saving checkpoint at iteration $(i_m)...")
        CSV.write(checkpoint_file, df_manzanas)
    end
end

# Write final results.
local_file_name = "predios_estrategicos.csv"
CSV.write(local_file_name, df_manzanas)
println("Processing complete. Final data saved to ", local_file_name)

aws_file_name = "kg/$(local_file_name)"
aws_bucket = "landengines-data"

aws_julia.upload_csv_file_to_s3(conn_aws, aws_bucket, aws_file_name, local_file_name)

# Erase the checkpoint file now that processing is complete.
if isfile(checkpoint_file)
    rm(checkpoint_file)
    println("Checkpoint file erased.")
end




# Get data from Neo4j
# lista_poi_no_incluir = "['restaurant', 'park', 'school', 'parking', 'convenience', 'fast_food', 'playground', 'cafe', 
# 'pharmacy', 'kindergarten', 'bank', 'place_of_worship', 'supermarket', 'sports_centre', 'fuel', 'clinic', 'fountain', 
# 'garden', 'university', 'pub', 'courthouse', 'library', 'community_centre', 'police', 'department_store', 'theatre', 
# 'mobile_phone', 'electronics', 'doityourself', 'marketplace', 'fire_station', 'college', 'car_wash', 'hospital', 
# 'social_facility', 'gas', 'cinema', 'shopping_centre', 'sports_hall', 'townhall', 'stadium', 'dog_park', 'food_court', 
# 'public_building', 'vehicle_inspection', 'bus_station', 'prison', 'conference_centre', 'golf_course', 'monastery', 
# 'storage_rental', 'building_materials', 'post_box', 'motorcycle_parking', 'money_transfer', 'casino']"
