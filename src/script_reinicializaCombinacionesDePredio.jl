using LandValue

conn_LandValue = pg_julia.connection("LandValue", "postgres", "postgres")

query_combinaciones_str = """
select combi_predios_str, status, id from tabla_combinacion_predios
"""
df_combinaciones = pg_julia.query(conn_LandValue, query_combinaciones_str)

num_combi = size(df_combinaciones,1)
for i = 1:num_combi
    combi_i_str = df_combinaciones[i,1]
    id_i = df_combinaciones[i,3]
    display("Reinicializando predios: " * combi_i_str)

    cond_str = "=" * string(id_i)
    vecColumnNames = ["status", "id"]
    vecColumnValue = ["0", string(id_i)]
    pg_julia.modifyRow!(conn_LandValue, "tabla_combinacion_predios", vecColumnNames, vecColumnValue, "id", cond_str)
end