using LandValue, DotEnv

# Establece las conexiones a las Base de Datos
# conn_LandValue = pg_julia.connection("landengines", ENV["USER"], ENV["PW"], ENV["HOST"])

DotEnv.load("secrets.env") #Caso Docker
datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]

conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])

query_combi_locations = """
select * from combi_locations
"""
df_combi_locations = pg_julia.query(conn_LandValue, query_combi_locations)
numRows_combi, numCols_combi = size(df_combi_locations)

unique_lotes = df_combi_locations[:, "unique_lotes"]

for r = 1:numRows_combi
    id_combi_str = string(df_combi_locations[r, "id_combi_list"])
    unique_lotes_r = df_combi_locations[r, "unique_lotes"]
    vec_unique_lotes = eval(Meta.parse(replace(replace(replace(replace(string(unique_lotes_r), "{" => "["), "}" => "]")))))
    num_unique_lotes_r = length(vec_unique_lotes)

    combi_list_r = df_combi_locations[r, "combi_list"]
    vec_combi_list = eval(Meta.parse(replace(replace(replace(replace(string(combi_list_r), "{" => "["), "}" => "]")))))
    num_vec_combi_r = length(vec_combi_list)
    C_r = zeros(Int, num_vec_combi_r, num_unique_lotes_r)
    for k = 1:num_vec_combi_r
        for i = 1:num_unique_lotes_r
            if vec_unique_lotes[i] in vec_combi_list[k]
                C_r[k, i] = 1
            end
        end
    end
    x_opt = optimal_lot_selection(C_r)
    lotes_opt = vec_unique_lotes[x_opt .== 1]
  
end