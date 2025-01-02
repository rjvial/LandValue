using LandValue, DotEnv, DataFrames

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

df_manzanas = DataFrame(manzana_sii = unique_manzanas)
df_manzanas.predios_estrategicos .= ""

for i_m in eachindex(unique_manzanas)
    df_predios_combis_m = df_predios_combis[df_predios_combis.manzana_sii .== unique_manzanas[i_m], :]
    unique_combis_m = unique(df_predios_combis_m.id_combi)
    unique_codigo_predial_m = unique(df_predios_combis_m.codigo_predial)
    num_combis_m = length(unique_combis_m)
    num_codigo_predial_m = length(unique_codigo_predial_m)
    display("Trabajando en Manzana $(unique_manzanas[i_m]). Num Combis: $(num_combis_m). Num Predios: $(num_codigo_predial_m)")

    C_m = zeros(Int, num_combis_m, num_codigo_predial_m)
    for i_c in 1:num_combis_m, i_p in 1:num_codigo_predial_m
        if any(df_predios_combis_m.id_combi .== unique_combis_m[i_c] .&& 
               df_predios_combis_m.codigo_predial .== unique_codigo_predial_m[i_p])
            C_m[i_c, i_p] = 1
        end
    end
    x_opt = optimal_lot_selection(C_m)
    lotes_opt = string(unique_codigo_predial_m[x_opt .== 1])
    df_manzanas.predios_estrategicos[df_manzanas.manzana_sii .== unique_manzanas[i_m]] .= lotes_opt
end
