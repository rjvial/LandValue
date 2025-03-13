using LandValue, DotEnv, DataFrames, CSV

fileDir = "C:\\Users\\rjvia\\.Neo4jDesktop\\relate-data\\dbmss\\dbms-8d2802c9-5882-41ce-a9e4-257030275495\\import\\"


host = "neo4j://localhost:7687"
user = "neo4j"
password = "x67y1332"
conn = neo4j_julia.connection(host, user, password)

query_predios_combis = """
match (p:Predio)-[]-(c:Combi) 
return c.manzana_sii as manzana_sii, c.id_combi as id_combi, c.sup_combi as sup_combi, 
        p.codigo_predial as codigo_predial 
order by id_combi, codigo_predial
"""
df_predios_combis = neo4j_julia.cypher_to_dataframe(query_predios_combis, conn)
unique_manzanas = sort(unique(df_predios_combis.manzana_sii))

query_predios = """
match (p:Predio)-[]-(c:Combi)
return distinct p.codigo_predial as codigo_predial, p.sup_terreno as sup_terreno 
order by codigo_predial
"""
df_predios = neo4j_julia.cypher_to_dataframe(query_predios, conn)

df_manzanas = DataFrame(manzana_sii = unique_manzanas)
df_manzanas.predios_estrategicos .= ""
df_manzanas.num_predios_estrategicos .= 0


for i_m in eachindex(unique_manzanas)
    df_predios_combis_m = df_predios_combis[df_predios_combis.manzana_sii .== unique_manzanas[i_m], :]
    unique_combis_m = unique(df_predios_combis_m.id_combi)
    unique_codigo_predial_m = unique(df_predios_combis_m.codigo_predial)
    df_predios_m = filter(row -> row.codigo_predial in unique_codigo_predial_m, df_predios)
    num_combis_m = length(unique_combis_m)
    num_codigo_predial_m = length(unique_codigo_predial_m)
    display("Trabajando en Manzana $(unique_manzanas[i_m]). Num Combis: $(num_combis_m). Num Predios: $(num_codigo_predial_m)")

    if num_combis_m <= 25
        C_m = zeros(Int, num_combis_m, num_codigo_predial_m)
        for i_c in 1:num_combis_m, i_p in 1:num_codigo_predial_m
            if any(df_predios_combis_m.id_combi .== unique_combis_m[i_c] .&& 
                df_predios_combis_m.codigo_predial .== unique_codigo_predial_m[i_p])
                C_m[i_c, i_p] = 1
            end
        end
        x_opt = optimal_lot_selection(C_m, df_predios_m)
        predios_opt = string(unique_codigo_predial_m[x_opt .== 1])
        num_predios_opt = sum(x_opt)
        df_manzanas.predios_estrategicos[df_manzanas.manzana_sii .== unique_manzanas[i_m]] .= predios_opt
        df_manzanas.num_predios_estrategicos[df_manzanas.manzana_sii .== unique_manzanas[i_m]] .= num_predios_opt
    end
end

fileDir_node = fileDir * "predios_estrategicos.csv"

CSV.write(fileDir_node, df_manzanas)