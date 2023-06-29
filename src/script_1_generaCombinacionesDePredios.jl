using LandValue, DataFrames, DotEnv

# DotEnv.load("secrets.env") #Caso Docker
# datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
# datos_mygis_db = ["gis_data", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
# conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
# conn_gis_data = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])

conn_LandValue = pg_julia.connection("landengines_local", "postgres", "", "localhost")
conn_gis_data = pg_julia.connection("gis_data_local", "postgres", "", "localhost")

function obtieneDelta(codigo_predial, conn_gis_data)
    codPredialStr = replace(replace(string(codigo_predial), "[" => "("), "]" => ")")

    # Obtiene desde la base de datos los parametros del predio 
    display("Obtiene los parametros del predio de ajuste")
    @time dcn, sup_terreno_edif, ps_predio_db = queryCabida.query_datos_predio(conn_gis_data, "vitacura", codPredialStr)

    # Simplifica, corrige orientacion y escala del predio
    ps_predio_db = polyShape.setPolyOrientation(ps_predio_db, 1)
    ps_predio_db, dx, dy = polyShape.ajustaCoordenadas(ps_predio_db)

	return dx, dy
end

function obtienePrediosAltura(conn_gis_data, nombre_datos_predios_vitacura, comunaStr, dx, dy)

    #--------------------------------------------------------------------------------------------------------
    # Obtiene los predios pertenecientes a las zonas de edificación en altura 
    display("Obtiene los predios pertenecientes a las zonas de edificación en altura")

    query_check_predios_altura_str = """
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = '__predios_altura'
    """
    df_check_predios_altura = pg_julia.query(conn_gis_data, query_check_predios_altura_str)

    if isempty(df_check_predios_altura) # En caso que no exista la tabla __predios_altura

        # Obtiene los predios disponibles con potencial de altura         INMOB%', '%CONSTR%', '%HOTEL%', '%S.A%', '%EMBAJADA
        query_predios_altura_str = """
        	CREATE TABLE __predios_altura AS
            
        	WITH predios_altura AS (SELECT codigo_predial, num_roles, zona, num_pisos_total, altura_max_total, ST_Transform(geom_predios,5361) as geom
        			FROM datos_predios_vitacura__ 
        			WHERE num_pisos_total >= 4 AND num_roles = 1 AND sup_construccion < sup_terreno_edif AND codigo_predial not in (SELECT anteproyectos_vitacura.codigo_predial 
        																					FROM anteproyectos_vitacura)),
        		predios_inter_poi AS (SELECT predios_altura.codigo_predial as codigo_predial
        			FROM predios_altura JOIN poi_vitacura on st_intersects(predios_altura.geom, ST_Transform(poi_vitacura.geom_poi,5361))
        			WHERE poi_vitacura.poi_subtype NOT IN ('swimming_pool', 'commercial') AND poi_vitacura.poi_type <> 'shop'),
        		points_inter_vitacura AS (SELECT ST_Transform(poi_vitacura_points.geom,5361) as geom  
        			FROM division_comunal JOIN poi_vitacura_points on st_contains(ST_Transform(division_comunal.geom,5361), ST_Transform(poi_vitacura_points.geom,5361))
        			WHERE poi_vitacura_points.osm_subtype NOT IN ('swimming_pool', 'commercial') AND poi_vitacura_points.osm_type <> 'shop' AND division_comunal.nom_com = 'Vitacura'),
        		predios_inmobiliarias AS (select geom_predios as geom, codigo_predial from datos_predios_vitacura__ where UPPER(propietario) LIKE any(array['%INMOB%', '%CONSTR%', '%HOTEL%', '%S.A%', '%EMBAJADA%']))

        	SELECT predios_altura.geom as geom, ST_AsText(predios_altura.geom) as predios_str, predios_altura.codigo_predial
        	FROM predios_altura 
        	WHERE 	predios_altura.codigo_predial not in (SELECT predios_inter_poi.codigo_predial as codigo_predial FROM predios_inter_poi) and 
        			predios_altura.codigo_predial not in (SELECT predios_altura.codigo_predial as codigo_predial
        					FROM predios_altura JOIN points_inter_vitacura on st_contains(predios_altura.geom, points_inter_vitacura.geom) ) and
        			predios_altura.codigo_predial not in (SELECT predios_inmobiliarias.codigo_predial from predios_inmobiliarias)
        """
        query_predios_altura_str = replace(query_predios_altura_str, "comunaStr_" => comunaStr)
        query_predios_altura_str = replace(query_predios_altura_str, "datos_predios_vitacura__" => nombre_datos_predios_vitacura)
        pg_julia.query(conn_gis_data, query_predios_altura_str)

    end
    query_predios_altura_str = """
    select __predios_altura.predios_str from __predios_altura where exists (select 1 from __predios_altura)
    """
    df_predios_altura = pg_julia.query(conn_gis_data, query_predios_altura_str)
    ps_predios_altura = polyShape.astext2polyshape(df_predios_altura.predios_str)
    ps_predios_altura = polyShape.ajustaCoordenadas(ps_predios_altura, dx, dy)
    ps_predios_altura = polyShape.setPolyOrientation(ps_predios_altura, 1)
	return ps_predios_altura
end

function obtieneManzanasAltura(conn_gis_data, nombre_datos_predios_vitacura, comunaStr, dx, dy)
    #--------------------------------------------------------------------------------------------------------
    # Obtiene las manzanas que contienen predios aptos para edificación en altura 
    display("Obtiene las manzanas que contienen predios aptos para edificación en altura")

    query_check_manzanas_altura_str = """
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = '__manzanas_altura'
    """
    df_check_manzanas_altura = pg_julia.query(conn_gis_data, query_check_manzanas_altura_str)

    if isempty(df_check_manzanas_altura) # En caso que no exista la tabla __manzanas_altura

        # Obtiene las manzanas con predios que tienen potencial de altura
        query_manzanas_altura_str = """
        	CREATE TABLE __manzanas_altura AS
        	WITH predios_altura AS (select geom from __predios_altura),
        		manzanas_vitacura AS (select id, ST_Transform(datos_manzanas_vitacura_2017.geom, 5361) as geom 
        							from datos_manzanas_vitacura_2017 where datos_manzanas_vitacura_2017.comuna = 'VITACURA')

        		select distinct manzanas_vitacura.id, manzanas_vitacura.geom as geom, ST_AsText(manzanas_vitacura.geom) as manzanas_str
        			from manzanas_vitacura join predios_altura on st_contains(manzanas_vitacura.geom, predios_altura.geom)
                    order by manzanas_vitacura.id
        """
        query_manzanas_altura_str = replace(query_manzanas_altura_str, "comunaStr_" => comunaStr)
        query_manzanas_altura_str = replace(query_manzanas_altura_str, "datos_predios_vitacura__" => nombre_datos_predios_vitacura)
        pg_julia.query(conn_gis_data, query_manzanas_altura_str)
    end

    query_manzanas_altura_str = """
    select __manzanas_altura.id, __manzanas_altura.manzanas_str from __manzanas_altura
    """
    df_manzanas_altura = pg_julia.query(conn_gis_data, query_manzanas_altura_str)
    ps_manzanas_altura = polyShape.astext2polyshape(df_manzanas_altura.manzanas_str)
    ps_manzanas_altura = polyShape.ajustaCoordenadas(ps_manzanas_altura, dx, dy)
    ps_manzanas_altura = polyShape.setPolyOrientation(ps_manzanas_altura, 1)

	num_manzanas_altura = size(df_manzanas_altura, 1)
    conjunto_manzanas = sort(unique(df_manzanas_altura[:, "id"]))

	return num_manzanas_altura, conjunto_manzanas
end

function generaCombinaciones(conjunto_manzanas, nombre_tabla_combinacion_predios, conn_LandValue, area_lote_lb, area_lote_ub, area_predio_lb, area_predio_ub, num_lote_max, largo_compartido_min)
    
    #--------------------------------------------------------------------------------------------------------
    # Genera tabla con las combinaciones de predios por manazana
    query_str = """ 
    CREATE TABLE IF NOT EXISTS public.tabla_combinacion_predios_str
    (
        "combi_predios_str" text,
    	"status" int,
        "manzana_id" int,
    	"num_lotes" int,
    	"area_predio" double precision,
    	"area_max_lote" double precision,
    	"area_min_lote" double precision,
        "ps_combi" text,
        id bigint NOT NULL
        )
    """
	query_str = replace(query_str, "tabla_combinacion_predios_str" => nombre_tabla_combinacion_predios)
    pg_julia.query(conn_LandValue, query_str)

    for num_manzana in conjunto_manzanas
        display("Manzana N°: " * string(num_manzana) )

        # Obtiene los predios disponibles en una manzana específica
        display("Obtiene los predios disponibles en una manzana específica")
        num_manzana_str = string(num_manzana)
        query_predios_manzana_str = """
        WITH manzana_seleccionada AS (select __manzanas_altura.id, __manzanas_altura.geom as geom from __manzanas_altura where __manzanas_altura.id = num_str)
        SELECT __predios_altura.predios_str, __predios_altura.geom, __predios_altura.codigo_predial
        FROM manzana_seleccionada join __predios_altura on st_intersects(manzana_seleccionada.geom, __predios_altura.geom)
        """
        query_predios_manzana_str = replace(query_predios_manzana_str, "num_str" => num_manzana_str)
        df_predios_manzana = pg_julia.query(conn_gis_data, query_predios_manzana_str)
        if size(df_predios_manzana, 1) >= 1
            ps_predios_manzana = polyShape.astext2polyshape(df_predios_manzana.predios_str)
            ps_predios_manzana = polyShape.ajustaCoordenadas(ps_predios_manzana, dx, dy)
            ps_predios_manzana = polyShape.setPolyOrientation(ps_predios_manzana, 1)

            VV_predios_manzana = copy(ps_predios_manzana.Vertices)
            vec_area = polyShape.polyArea(ps_predios_manzana; sep_flag=true)
            flag_area_vec = (vec_area .> area_lote_lb) .* (vec_area .< area_lote_ub)
            VV_predios_manzana = VV_predios_manzana[flag_area_vec.==1]
            ps_predios_manzana = PolyShape(VV_predios_manzana, length(VV_predios_manzana))

            # Obtiene grafo que representa predios de la manzana
            vec_codigo_predial = string.(df_predios_manzana.codigo_predial[flag_area_vec[:].==1])

            num_lotes = length(vec_codigo_predial)

            print(vec_codigo_predial)

            if sum(flag_area_vec) >= 1
                if sum(flag_area_vec) >= 2
                    # Obtiene matriz de largo de lados compartidos por dos predios
                    length_mat = zeros(num_lotes, num_lotes)
                    adj_mat = zeros(Int, num_lotes, num_lotes)
                    for i = 1:num_lotes-1
                        p_i = polyShape.subShape(ps_predios_manzana, i)
                        p_i_ = polyShape.polyExpand(p_i, 0.1)
                        for j = i+1:num_lotes
                            p_j = polyShape.subShape(ps_predios_manzana, j)
                            p_j_ = polyShape.polyExpand(p_j, 0.1)
                            p_ij = polyShape.polyIntersect(p_i_, p_j_)
                            largo_ij = polyShape.polyArea(p_ij) / 0.2
                            if largo_ij >= largo_compartido_min
                                adj_mat[i, j] = 1
                            end
                            length_mat[i, j] = largo_ij
                        end
                    end
                    adj_mat = adj_mat .+ adj_mat'
                    combi_predios = graphMod.node_combis(adj_mat)

                else
                    adj_mat = 1
                    combi_predios = [[1]]
                end

                combi_predios = combi_predios[length.(combi_predios) .<= num_lote_max]
                length_combi_predios = length(combi_predios)
                display(length_combi_predios)

                vec_area_combi = zeros(length_combi_predios, 1)
                for i = 1:length_combi_predios
                    combi_i = combi_predios[i]
                    #ps_i = polyShape.polyUnion(polyShape.subShape(ps_predios_manzana, combi_i))
                    ps_i = polyShape.polyExpand(polyShape.polyExpand(polyShape.subShape(ps_predios_manzana, combi_i),0.02),-0.02)

                    if ps_i.NumRegions == 1 #Si la unión genera un sólo polígono --> predios están conectados
                        area_i = polyShape.polyArea(ps_i)
                        vec_codigo_predial_i = vec_codigo_predial[combi_i]
                        if area_i >= area_predio_lb && area_i <= area_predio_ub && length(combi_i) <= num_lote_max
                            display("Largo Combi Predios: " * string(length(vec_codigo_predial_i)))
                            vec_area_ps_i = polyShape.polyArea(polyShape.subShape(ps_predios_manzana, combi_i), sep_flag=true)
                            area_max_lote = maximum(vec_area_ps_i)
                            area_min_lote = minimum(vec_area_ps_i)
                            ps_str = "PolyShape([" * string(ps_i.Vertices[1]) * "],1)"                        
                            vecColumnNames = ["combi_predios_str", "status", "manzana_id", "num_lotes", "area_predio", "area_max_lote", "area_min_lote", "ps_combi", "id"]
                            vecColumnValue = [vec_codigo_predial_i, 0, num_manzana, length(combi_i), area_i, area_max_lote, area_min_lote, ps_str, string(i)]
                            pg_julia.insertRow!(conn_LandValue, nombre_tabla_combinacion_predios, vecColumnNames, vecColumnValue, :id)
                        end
                    end
                end
            end
        end
    end

    query_tabla_combinacion_str = """
    SELECT *
    FROM public.tabla_combinacion_predios_str
    """
    query_tabla_combinacion_str = replace(query_tabla_combinacion_str, "tabla_combinacion_predios_str" => nombre_tabla_combinacion_predios)
    df_tabla_combinacion = pg_julia.query(conn_LandValue, query_tabla_combinacion_str)
    
    return df_tabla_combinacion
end

function concatenate_vectors(v::Vector{Vector{T}}) where T
    concatenated = v[1]
    for i = 2:length(v)
        concatenated = vcat(concatenated, v[i])
    end
    return [concatenated]
end

function generaCombinacionesFinales(df_predios_combi, df_predios, nombre_tabla_combinacion_predios, conn_LandValue, area_lote_lb, area_lote_ub, area_predio_lb, area_predio_ub, num_lote_max, largo_compartido_min)
    
    # Genera tabla con las combinaciones de predios por manazana
    query_str = """ 
    CREATE TABLE IF NOT EXISTS public.tabla_combinacion_predios_str
    (
        "combi_predios_str" text,
    	"status" int,
        "manzana_id" int,
    	"num_lotes" int,
    	"area_predio" double precision,
    	"area_max_lote" double precision,
    	"area_min_lote" double precision,
        "ps_combi" text,
        id bigint NOT NULL    
        )
    """
	query_str = replace(query_str, "tabla_combinacion_predios_str" => nombre_tabla_combinacion_predios)
    pg_julia.query(conn_LandValue, query_str)

    conjunto_manzanas = sort(unique(df_predios_combi[:,"manzana_id"]))

    for num_manzana in conjunto_manzanas   # Manzana N°: 2738
        display("##################################")
        display("# Manzana N°: " * string(num_manzana))
        display("##################################")

        df_predios_combi_manzana = filter(:manzana_id => m-> m == num_manzana, df_predios_combi)

        # Obtiene los predios disponibles en una manzana específica
        display("Obtiene los predios disponibles en una manzana específica")
        vec_ps_predios_manzana = eval.(Meta.parse.(df_predios_combi_manzana[:, "ps_combi"]))
        vec_predios_manzana = df_predios_combi_manzana[:, "combi_predios_str"]
        vec_codigo_predial = deepcopy(vec_predios_manzana)
        vec_codigo_predial = eval.(Meta.parse.(replace.(vec_codigo_predial, "\"" => "")))
        vec_area = polyShape.polyArea.(vec_ps_predios_manzana)
        vec_id = rownumber.(eachrow(df_predios_combi_manzana))
        flag_area_vec = (vec_area .> area_lote_lb) .* (vec_area .< area_lote_ub)
        vec_ps_predios_manzana = vec_ps_predios_manzana[flag_area_vec]
        vec_id = vec_id[flag_area_vec]
        vec_codigo_predial = vec_codigo_predial[flag_area_vec]
        vec_area = vec_area[flag_area_vec]

        # Obtiene combinaciones factibles de predios en la manzana
        display("Obtiene combinaciones factibles de predios en la manzana")
        vec_id_str = string.(vec_id)
        num_lotes = length(vec_id_str)
        print(vec_id_str)
        combi_predios = []
        if sum(flag_area_vec) >= 2
            # Obtiene matriz de adyacencia a partir de la magnitud del largo compartido
            length_mat = zeros(num_lotes, num_lotes)
            adj_mat = zeros(Int, num_lotes, num_lotes)
            for i = 1:num_lotes-1
                p_i = vec_ps_predios_manzana[i]
                p_i_ = polyShape.polyExpand(p_i, 0.1)
                for j = i+1:num_lotes
                    p_j = vec_ps_predios_manzana[j]
                    p_j_ = polyShape.polyExpand(p_j, 0.1)
                    p_ij = polyShape.polyIntersect(p_i_, p_j_)
                    largo_ij = polyShape.polyArea(p_ij) / 0.2
                    if largo_ij >= largo_compartido_min
                        adj_mat[i, j] = 1
                    end
                    length_mat[i, j] = largo_ij
                end
            end
            adj_mat = adj_mat .+ adj_mat'

            # Calcula todas las combinaciones de nodos que están conectados
            combi_predios = graphMod.node_combis(adj_mat)
        elseif sum(flag_area_vec) >= 1
            adj_mat = 1
            combi_predios = [[1]]
        end

        display("Genera predio formado por la unión de lotes")
        length_combi_predios = length(combi_predios)
        display(length_combi_predios)
        vec_combi_manzana = []
        for i = 1:length_combi_predios
            combi_i = combi_predios[i]
            ps_i = polyShape.polyUnion(vec_ps_predios_manzana[combi_i])
            ps_i = polyShape.polyExpand(polyShape.polyExpand(ps_i,0.02),-0.02)

            if ps_i.NumRegions == 1 #Si la unión genera un sólo polígono --> predios están conectados
                area_i = polyShape.polyArea(ps_i)
                vec_codigo_predial_i = sort(unique(concatenate_vectors(vec_codigo_predial[combi_i])[1]))
                if i==1
                    push!(vec_combi_manzana, vec_codigo_predial_i)
                    flag_repetido = false
                elseif vec_codigo_predial_i in vec_combi_manzana
                    display("######### Repetido #############")
                    flag_repetido = true
                else
                    push!(vec_combi_manzana, vec_codigo_predial_i)
                    flag_repetido = false
                end

                if flag_repetido == false && area_i >= area_predio_lb && area_i <= area_predio_ub && length(vec_codigo_predial_i) <= num_lote_max
                    display("Largo Combi Predios: " * string(length(vec_codigo_predial_i)))
                    df_predios_i = filter(r -> r.codigo_predial in vec_codigo_predial_i, df_predios)
                    ps_predios_i = polyShape.astext2polyshape(df_predios_i.geom)
                    ps_predios_i = polyShape.ajustaCoordenadas(ps_predios_i, dx, dy)
                    ps_predios_i = polyShape.setPolyOrientation(ps_predios_i, 1)
                    vec_area_ps_i =  polyShape.polyArea(ps_predios_i, sep_flag=true)
                    area_max_lote = maximum(vec_area_ps_i)
                    area_min_lote = minimum(vec_area_ps_i)
                    ps_str = "PolyShape([" * string(ps_i.Vertices[1]) * "],1)"                        
                    vecColumnNames = ["combi_predios_str", "status", "manzana_id", "num_lotes", "area_predio", "area_max_lote", "area_min_lote", "ps_combi", "id"]
                    vecColumnValue = [string(vec_codigo_predial_i), 0, num_manzana, length(vec_codigo_predial_i), area_i, area_max_lote, area_min_lote, ps_str, string(i)]
                    pg_julia.insertRow!(conn_LandValue, nombre_tabla_combinacion_predios, vecColumnNames, vecColumnValue, :id)
                end
            end
        end

    end

    query_delete_aux_str = """
    	DROP TABLE __predios_altura, __manzanas_altura;
    """
    pg_julia.query(conn_gis_data, query_delete_aux_str)

end

nombre_datos_predios_vitacura = "datos_predios_vitacura"
comunaStr = "vitacura"
codigo_predial = [151600041700009]
dx, dy = obtieneDelta(codigo_predial, conn_gis_data)

ps_predios_altura = obtienePrediosAltura(conn_gis_data, nombre_datos_predios_vitacura, comunaStr, dx, dy)
num_manzanas_altura, conjunto_manzanas = obtieneManzanasAltura(conn_gis_data, nombre_datos_predios_vitacura, comunaStr, dx, dy)

query_predios_str = """SELECT codigo_predial, ST_AsText(ST_Transform(geom_predios,5361)) as geom
                    FROM datos_predios_vitacura__
                   """
query_predios_str = replace(query_predios_str, "datos_predios_vitacura__" => nombre_datos_predios_vitacura)
df_predios = pg_julia.query(conn_gis_data, query_predios_str)
ps_predios = polyShape.astext2polyshape(df_predios.geom)
ps_predios = polyShape.ajustaCoordenadas(ps_predios, dx, dy)
ps_predios = polyShape.setPolyOrientation(ps_predios, 1)

#### 2877
#### 2730 = 23 (1516002173000XX)


nombre_tabla_combinacion_predios = "tabla_predios_chicos"
# ########################################################
# filtros
# ########################################################
area_lote_lb = 100
area_lote_ub = 400 
area_predio_lb = 400 
area_predio_ub = 4000
num_lote_max = 2 
largo_compartido_min = 20
########################################################
df_tabla_chicos = generaCombinaciones(conjunto_manzanas, nombre_tabla_combinacion_predios, conn_LandValue, area_lote_lb, area_lote_ub, area_predio_lb, area_predio_ub, num_lote_max, largo_compartido_min)


nombre_tabla_combinacion_predios = "tabla_predios_grandes"
# ########################################################
# filtros
# ########################################################
area_lote_lb = 400
area_lote_ub = 3000
area_predio_lb = 400
area_predio_ub = 3000
num_lote_max = 1
largo_compartido_min = 20
########################################################
df_tabla_grandes = generaCombinaciones(conjunto_manzanas, nombre_tabla_combinacion_predios, conn_LandValue, area_lote_lb, area_lote_ub, area_predio_lb, area_predio_ub, num_lote_max, largo_compartido_min)

df_predios_combi = vcat(df_tabla_grandes, df_tabla_chicos)


nombre_tabla_combinacion_predios = "tabla_combinacion_predios"
#########################################################
# filtros
#########################################################
area_lote_lb = 450 #400
area_lote_ub = 3000
area_predio_lb = 1200
area_predio_ub = 4000
num_lote_max = 12
largo_compartido_min = 18
#########################################################
generaCombinacionesFinales(df_predios_combi, df_predios, nombre_tabla_combinacion_predios, conn_LandValue, area_lote_lb, area_lote_ub, area_predio_lb, area_predio_ub, num_lote_max, largo_compartido_min)

query_borra_tablas_aux_str = """DROP TABLE tabla_predios_chicos, tabla_predios_grandes"""
pg_julia.query(conn_LandValue, query_borra_tablas_aux_str)


