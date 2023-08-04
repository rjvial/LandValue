using LandValue, DotEnv

# Establece las conexiones a las Base de Datos
# conn_LandValue = pg_julia.connection("landengines", ENV["USER"], ENV["PW"], ENV["HOST"])

DotEnv.load("secrets.env")
datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]

conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])

query_combi_locations = """
select * from combi_locations
order by id_combi_list ASC
"""
# query_combi_locations = """
# select * from combi_locations
# where id_max_gap = 4268
# """

df_combi_locations = pg_julia.query(conn_LandValue, query_combi_locations)
numRows_combi, numCols_combi = size(df_combi_locations)

display("Agrega columna a combi_locations")
query_add_column = """
ALTER TABLE combi_locations
    ADD COLUMN IF NOT EXISTS lotes_estrategicos text
"""
pg_julia.query(conn_LandValue, query_add_column)

for r = 1:numRows_combi
    display("Agregando lotes estrategicos a la localidad N°" * string(r))
    id_combi_str = string(df_combi_locations[r, "id_combi_list"])
    unique_lotes_r = df_combi_locations[r, "unique_lotes"]
    vec_unique_lotes = eval(Meta.parse(replace(replace(replace(replace(string(unique_lotes_r), "{" => "["), "}" => "]")))))
    num_unique_lotes_r = length(vec_unique_lotes)

    num_lotes_combi_r = eval(Meta.parse(df_combi_locations[r, "num_lotes_combi"]))
    flag_num_lotes_combi = num_lotes_combi_r .>= 1

    sign_combi_r = eval(Meta.parse(df_combi_locations[r, "sign_combi_vec"]))
    flag_sign_combi = sign_combi_r .>= 1

    combi_list_r = df_combi_locations[r, "combi_list"]
    vec_combi_list = eval(Meta.parse(replace(replace(replace(replace(string(combi_list_r), "{" => "["), "}" => "]")))))
    
    try
        vec_combi_list = vec_combi_list[flag_num_lotes_combi .& flag_sign_combi .>= 1]
        num_vec_combi_r = length(vec_combi_list)

        if num_vec_combi_r >= 1
            C_r = zeros(Int, num_vec_combi_r, num_unique_lotes_r)
            for k = 1:num_vec_combi_r
                for i = 1:num_unique_lotes_r
                    if vec_unique_lotes[i] in vec_combi_list[k]
                        C_r[k, i] = 1
                    end
                end
            end
            x_opt = optimal_lot_selection(C_r)
            lotes_opt = string(vec_unique_lotes[x_opt .== 1])
        elseif sum(flag_num_lotes_combi) == 0 && sum(flag_sign_combi) == 0
            lotes_opt = "-333333"
        elseif sum(flag_num_lotes_combi) == 0
            lotes_opt = replace(replace(string(combi_list_r), "{" => ""), "}" => "")
        else 
            lotes_opt = "-222222"
        end
    catch
        lotes_opt = "-999999"
    end

    lotes_opt = "\'" * lotes_opt * "\'"
    query_ = """
        UPDATE combi_locations SET lotes_estrategicos = $lotes_opt
        WHERE id_combi_list = $r
    """
    pg_julia.query(conn_LandValue, query_)

end