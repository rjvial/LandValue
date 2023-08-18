using LandValue, DotEnv

DotEnv.load("secrets.env") #Caso Docker
datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
datos_mygis_db = ["gis_data", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
# datos_LandValue = ["landengines_local", "postgres", "", "localhost"]
# datos_mygis_db = ["gis_data_local", "postgres", "", "localhost"]

conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
conn_mygis_db = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])


# Parametros
delta_porcentual = 0.1
minGap = 0. #0.2


query_combi_locations = """
select id_combi_list from combi_locations
order by id_combi_list ASC
"""
df_combi_locations = pg_julia.query(conn_LandValue, query_combi_locations)
numRows_locations, aux = size(df_combi_locations)

display("Agrega columna a combi_locations")
query_add_column = """
    ALTER TABLE combi_locations
    ADD COLUMN IF NOT EXISTS util_esp_combi double precision,
    ADD COLUMN IF NOT EXISTS id_lotes_pos_gap text,
    ADD COLUMN IF NOT EXISTS geom_lotes_pos geometry(Geometry,4326),
    ADD COLUMN IF NOT EXISTS optimal_price_vec text,
    ADD COLUMN IF NOT EXISTS superficie_lote_vec text,
    ADD COLUMN IF NOT EXISTS optimal_unit_price_vec text
"""
pg_julia.query(conn_LandValue, query_add_column)

for r = 1:numRows_locations


    query_valor_combi_r = """
    select id, combi_predios, terreno_costo, valor_mercado_combi from tabla_resultados_cabidas
    where id_combi_list = $r and gap >= $minGap
    order by id ASC
    """
    df_valor_combi_r = pg_julia.query(conn_LandValue, query_valor_combi_r)

    try
        if !isempty(df_valor_combi_r) 
            display("Maximizando utilidad esperada de la Localidad N° " * string(r))

            id_combi_vec = sort(df_valor_combi_r[:,"id"])
            num_combi_pos = length(id_combi_vec)

            id_prop_vec = []
            for i = 1:num_combi_pos
                id_prop_vec_str = df_valor_combi_r[i,"combi_predios"]
                id_prop_vec_i = eval(Meta.parse(id_prop_vec_str))
                id_prop_vec = union(id_prop_vec, id_prop_vec_i)
            end
            id_prop_vec = sort(id_prop_vec)
            num_lotes = length(id_prop_vec)
            id_combi_list_r = replace(replace(string(id_prop_vec), "Any[" => "("), "]" => ")")

            query_sup_prop_r = """
            select codigo_predial, sup_terreno_edif from datos_predios_vitacura
            where codigo_predial in $id_combi_list_r
            order by codigo_predial ASC
            """
            df_sup_prop_r = pg_julia.query(conn_mygis_db, query_sup_prop_r)

            query_valor_prop_r = """
            select rol as codigo_predial, precio_estimado_final from tabla_propiedades
            where rol in $id_combi_list_r
            order by rol ASC
            """
            df_valor_prop_r = pg_julia.query(conn_LandValue, query_valor_prop_r)

            C = zeros(Int, num_combi_pos, num_lotes)
            for i = 1:num_combi_pos
                id_prop_vec_str = df_valor_combi_r[i,"combi_predios"]
                id_prop_vec_i = eval(Meta.parse(id_prop_vec_str))
                for j in eachindex(id_prop_vec_i)
                    pos_j = findfirst(x -> x==id_prop_vec_i[j], id_prop_vec)
                    C[i, pos_j] = 1
                end
            end

            # A = graphMod.Combi2Adjacency(C)
            # graphMod.graphPlot(A)

            valorMercado_lotes = zeros(num_lotes,1)
            superficie_lotes = zeros(num_lotes,1)
            for j in eachindex(id_prop_vec)
                valorMercado_lotes[j] = df_valor_prop_r[df_valor_prop_r.codigo_predial .== id_prop_vec[j], "precio_estimado_final"][1]
                superficie_lotes[j] = df_sup_prop_r[df_sup_prop_r.codigo_predial .== id_prop_vec[j], "sup_terreno_edif"][1]
            end

            valorInmobiliario_combis = zeros(num_combi_pos,1)
            for i = 1:num_combi_pos
                valorInmobiliario_combis[i] = df_valor_combi_r[df_valor_combi_r.id .== id_combi_vec[i], "terreno_costo"][1]
            end

            xopt_r, util_opt_r, unit_price_r = optimal_pricing(C, valorMercado_lotes, superficie_lotes, valorInmobiliario_combis, delta_porcentual)
            display(util_opt_r)
            display(xopt_r)
            

        else
            util_opt_r = -111111
        end

        query_ = """
            UPDATE combi_locations SET util_esp_combi = $util_opt_r
            WHERE id_combi_list = $r
        """
        pg_julia.query(conn_LandValue, query_)
        query_ = """
            UPDATE combi_locations SET id_lotes_pos_gap = '$id_combi_list_r'
            WHERE id_combi_list = $r
        """
        pg_julia.query(conn_LandValue, query_)


        query_geom = """
            select ST_AsText(ST_Union(ST_Transform(geom_predios, 4326))) as geom_str 
            from datos_predios_vitacura where codigo_predial in $id_combi_list_r
        """
        df_lotes_pos_geom = pg_julia.query(conn_mygis_db, query_geom)

        df_lotes_pos_aux = "\'" * df_lotes_pos_geom[1,"geom_str"] * "\'"
        query_ = """
            UPDATE combi_locations SET geom_lotes_pos = st_geomfromtext($df_lotes_pos_aux)
            WHERE id_combi_list = $r
        """
        pg_julia.query(conn_LandValue, query_)


        xopt_str = string(xopt_r)
        query_ = """
            UPDATE combi_locations SET optimal_price_vec = '$xopt_str'
            WHERE id_combi_list = $r
        """
        pg_julia.query(conn_LandValue, query_)
        superficie_lotes_str = string(superficie_lotes)
        query_ = """
            UPDATE combi_locations SET superficie_lote_vec = '$superficie_lotes_str'
            WHERE id_combi_list = $r
        """
        pg_julia.query(conn_LandValue, query_)
        query_ = """
            UPDATE combi_locations SET optimal_unit_price_vec = '$unit_price_r'
            WHERE id_combi_list = $r
        """
        pg_julia.query(conn_LandValue, query_)
    catch
        query_ = """
            UPDATE combi_locations SET util_esp_combi = -999999
            WHERE id_combi_list = $r
        """
        display("Error")
    end


end

# pg_dump -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres -d landengines_dev -t "combi_locations" | psql -d landengines -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres