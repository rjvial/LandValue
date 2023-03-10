using LandValue

comunaStr = "vitacura"
codigo_predial = [151600041300008]
codPredialStr = replace(replace(string(codigo_predial),"[" => "("),"]" => ")")

conn_LandValue = pg_julia.connection("LandValue", "postgres", "postgres")
conn_mygis_db = pg_julia.connection("mygis_db", "postgres", "postgres")

# Obtiene desde la base de datos los parametros del predio 
display("Obtiene desde la base de datos los parametros del predio")
@time dcn, sup_terreno_edif, ps_predio_db = queryCabida.query_datos_predio(conn_mygis_db, "vitacura", codPredialStr)

# Simplifica, corrige orientacion y escala del predio
ps_predio_db = polyShape.setPolyOrientation(ps_predio_db,1)
ps_predio_db, dx, dy = polyShape.ajustaCoordenadas(ps_predio_db)
ps_predio_db = polyShape.polyUnion(ps_predio_db)
ps_predio = polyShape.shapeSimplify(ps_predio_db, 1.)
ps_predio = polyShape.polyEliminaColineales(ps_predio)
ps_predio = polyShape.polyEliminaRepetidos(ps_predio)


#--------------------------------------------------------------------------------------------------------
# Obtiene los predios pertenecientes a las zonas de edificación en altura 
display("Obtiene los predios pertenecientes a las zonas de edificación en altura")

query_check_predios_altura_str = """
SELECT 1 FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = '__predios_altura'
"""
df_check_predios_altura = pg_julia.query(conn_mygis_db, query_check_predios_altura_str)

if isempty(df_check_predios_altura) # En caso que no exista la tabla __predios_altura

	# Obtiene los predios disponibles con potencial de altura
	query_predios_altura_str = """
		CREATE TABLE __predios_altura AS
		WITH predios_altura AS (SELECT codigo_predial, num_roles, zona, num_pisos_total, altura_max_total, ST_Transform(geom_predios,5361) as geom
				FROM datos_predios_vitacura 
				WHERE num_pisos_total >= 4 AND num_roles = 1 AND sup_construccion < sup_terreno_edif AND codigo_predial not in (SELECT anteproyectos_vitacura.codigo_predial 
																						FROM anteproyectos_vitacura)),
			predios_inter_poi AS (SELECT predios_altura.codigo_predial as codigo_predial
				FROM predios_altura JOIN poi_vitacura on st_intersects(predios_altura.geom, ST_Transform(poi_vitacura.geom_poi,5361))
				WHERE poi_vitacura.poi_subtype <> 'swimming_pool'),
			points_inter_vitacura AS (SELECT ST_Transform(poi_vitacura_points.geom,5361) as geom  
				FROM division_comunal JOIN poi_vitacura_points on st_contains(ST_Transform(division_comunal.geom,5361), ST_Transform(poi_vitacura_points.geom,5361))
				WHERE poi_vitacura_points.osm_subtype <> 'swimming_pool' AND division_comunal.nom_com = 'Vitacura'),
			predios_inmobiliarias AS (select geom_predios as geom, codigo_predial from datos_predios_vitacura where UPPER(propietario) LIKE any(array['%INMOB%', '%CONSTR%', '%HOTEL%', '%S.A%', '%EMBAJADA%']))
		SELECT predios_altura.geom as geom, ST_AsText(predios_altura.geom) as predios_str, predios_altura.codigo_predial
		FROM predios_altura 
		WHERE 	predios_altura.codigo_predial not in (SELECT predios_inter_poi.codigo_predial as codigo_predial FROM predios_inter_poi) and 
				predios_altura.codigo_predial not in (SELECT predios_altura.codigo_predial as codigo_predial
						FROM predios_altura JOIN points_inter_vitacura on st_contains(predios_altura.geom, points_inter_vitacura.geom) ) and
				predios_altura.codigo_predial not in (SELECT predios_inmobiliarias.codigo_predial from predios_inmobiliarias)
	"""
	query_predios_altura_str = replace(query_predios_altura_str, "comunaStr_" => comunaStr)
	pg_julia.query(conn_mygis_db, query_predios_altura_str)

end
query_predios_altura_str = """
select __predios_altura.predios_str from __predios_altura where exists (select 1 from __predios_altura)
"""
df_predios_altura = pg_julia.query(conn_mygis_db, query_predios_altura_str)
ps_predios_altura = polyShape.astext2polyshape(df_predios_altura.predios_str)
ps_predios_altura = polyShape.ajustaCoordenadas(ps_predios_altura, dx, dy)
ps_predios_altura = polyShape.setPolyOrientation(ps_predios_altura,1)
fig, ax, ax_mat = polyShape.plotPolyshape2D(ps_predios_altura, "red", .2)


#--------------------------------------------------------------------------------------------------------
# Obtiene las manzanas que contienen predios aptos para edificación en altura 
display("Obtiene las manzanas que contienen predios aptos para edificación en altura")

query_check_manzanas_altura_str = """
SELECT 1 FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = '__manzanas_altura'
"""
df_check_manzanas_altura = pg_julia.query(conn_mygis_db, query_check_manzanas_altura_str)

if isempty(df_check_manzanas_altura) # En caso que no exista la tabla __manzanas_altura

	# Obtiene las manzanas con predios que tienen potencial de altura
	query_manzanas_altura_str = """
		CREATE TABLE __manzanas_altura AS
		WITH predios_altura AS (SELECT codigo_predial, num_roles, zona, num_pisos_total, altura_max_total, ST_Transform(geom_predios,5361) as geom
				FROM datos_predios_vitacura 
				WHERE num_pisos_total >= 4 AND num_roles = 1 AND sup_construccion < sup_terreno_edif AND codigo_predial not in (SELECT anteproyectos_vitacura.codigo_predial 
																						FROM anteproyectos_vitacura)),
			predios_inter_poi AS (SELECT predios_altura.codigo_predial as codigo_predial
				FROM predios_altura JOIN poi_vitacura on st_intersects(predios_altura.geom, ST_Transform(poi_vitacura.geom_poi,5361))
				WHERE poi_vitacura.poi_subtype <> 'swimming_pool'),
			points_inter_vitacura AS (SELECT ST_Transform(poi_vitacura_points.geom,5361) as geom  
				FROM division_comunal JOIN poi_vitacura_points on st_contains(ST_Transform(division_comunal.geom,5361), ST_Transform(poi_vitacura_points.geom,5361))
				WHERE poi_vitacura_points.osm_subtype <> 'swimming_pool' AND division_comunal.nom_com = 'Vitacura'),
			predios_inmobiliarias AS (select geom_predios as geom, codigo_predial from datos_predios_vitacura where UPPER(propietario) LIKE any(array['%INMOB%', '%CONSTR%', '%HOTEL%', '%S.A%', '%EMBAJADA%'])),
			predios_filtro AS (select predios_altura.geom as geom, predios_altura.codigo_predial
										FROM predios_altura 
										WHERE 	predios_altura.codigo_predial not in (SELECT predios_inter_poi.codigo_predial as codigo_predial FROM predios_inter_poi) and 
												predios_altura.codigo_predial not in (SELECT predios_altura.codigo_predial as codigo_predial
														FROM predios_altura JOIN points_inter_vitacura on st_contains(predios_altura.geom, points_inter_vitacura.geom) ) and
												predios_altura.codigo_predial not in (SELECT predios_inmobiliarias.codigo_predial from predios_inmobiliarias) ),
			manzanas_vitacura AS (select ST_Transform(datos_manzanas_vitacura_2017.geom, 5361) as geom 
								from datos_manzanas_vitacura_2017 where datos_manzanas_vitacura_2017.comuna = 'VITACURA')

			select distinct manzanas_vitacura.geom as geom, ST_AsText(manzanas_vitacura.geom) as manzanas_str
				from manzanas_vitacura join predios_filtro on st_contains(manzanas_vitacura.geom, predios_filtro.geom)
	"""
	query_manzanas_altura_str = replace(query_manzanas_altura_str, "comunaStr_" => comunaStr)
	pg_julia.query(conn_mygis_db, query_manzanas_altura_str)
end

query_manzanas_altura_str = """
select __manzanas_altura.manzanas_str from __manzanas_altura
"""
df_manzanas_altura = pg_julia.query(conn_mygis_db, query_manzanas_altura_str)
ps_manzanas_altura = polyShape.astext2polyshape(df_manzanas_altura.manzanas_str)
ps_manzanas_altura = polyShape.ajustaCoordenadas(ps_manzanas_altura, dx, dy)
ps_manzanas_altura = polyShape.setPolyOrientation(ps_manzanas_altura,1)
fig, ax, ax_mat = polyShape.plotPolyshape2D(ps_manzanas_altura, "blue", .2, fig=fig, ax=ax, ax_mat=ax_mat)


#--------------------------------------------------------------------------------------------------------
# Genera tabla con las combinaciones de predios por manazana
query_str = """ 
CREATE TABLE IF NOT EXISTS public.tabla_combinacion_predios
(
    "combi_predios_str" text,
	"status" int,
	"num_lotes" int,
	"area_predio" double precision,
	"area_max_lote" double precision,
	"area_min_lote" double precision,
    id bigint NOT NULL,
    CONSTRAINT tabla_combinacion_predios_pkey PRIMARY KEY (id)
)
"""
pg_julia.query(conn_LandValue, query_str)

num_manzanas_altura = size(df_manzanas_altura,1)



#########################################################
# filtros
#########################################################

area_lote_lb = 100; area_lote_ub = 3000
area_predio_lb = 1200; area_predio_ub = 4000
num_lote_max = 15
largo_compartido_min = 20

#########################################################


for num_manzana = 1:num_manzanas_altura
	display("Manzana N°: "*string(num_manzana))

	# Obtiene los predios disponibles en una manzana específica
	display("Obtiene los predios disponibles en una manzana específica")
	num_manzana_str = string(num_manzana - 1)
	query_predios_manzana_str = """
	WITH manzana_seleccionada AS (select __manzanas_altura.geom as geom from __manzanas_altura LIMIT 1 OFFSET num_str)
	SELECT __predios_altura.predios_str, __predios_altura.geom, __predios_altura.codigo_predial
	FROM manzana_seleccionada join __predios_altura on st_intersects(manzana_seleccionada.geom, __predios_altura.geom)
	"""
	query_predios_manzana_str = replace(query_predios_manzana_str, "num_str" => num_manzana_str)
	df_predios_manzana = pg_julia.query(conn_mygis_db, query_predios_manzana_str)
	ps_predios_manzana = polyShape.astext2polyshape(df_predios_manzana.predios_str)
	ps_predios_manzana = polyShape.ajustaCoordenadas(ps_predios_manzana, dx, dy)
	ps_predios_manzana = polyShape.setPolyOrientation(ps_predios_manzana,1)

	VV_predios_manzana = copy(ps_predios_manzana.Vertices)
	vec_area = polyShape.polyArea(ps_predios_manzana; sep_flag = true)
	flag_area_vec = (vec_area .> area_lote_lb) .*  (vec_area .< area_lote_ub)
	VV_predios_manzana = VV_predios_manzana[flag_area_vec .== 1]
	ps_predios_manzana = PolyShape(VV_predios_manzana, length(VV_predios_manzana))
	#fig, ax, ax_mat = polyShape.plotPolyshape2D(ps_predios_manzana, "black", 0.5, fig=fig, ax=ax, ax_mat=ax_mat)


	# Obtiene grafo que representa predios de la manzana
	vec_codigo_predial = string.(df_predios_manzana.codigo_predial[flag_area_vec[:] .== 1])

	num_lotes = length(vec_codigo_predial)

	print(vec_codigo_predial)

	if sum(flag_area_vec) >= 1 
		if sum(flag_area_vec) >= 2 
			# Obtiene matriz de largo de lados compartidos por dos predios
			length_mat = zeros(num_lotes, num_lotes)
			adj_mat = zeros(Int, num_lotes, num_lotes)
			for i = 1:num_lotes-1
				p_i = polyShape.subShape(ps_predios_manzana, i)
				p_i_= polyShape.polyExpand(p_i,.1)
				for j = i+1:num_lotes
					p_j = polyShape.subShape(ps_predios_manzana, j)
					p_j_= polyShape.polyExpand(p_j,.1)
					p_ij = polyShape.polyIntersect(p_i_,p_j_)
					largo_ij = polyShape.polyArea(p_ij)/.2
					if largo_ij >= largo_compartido_min
						adj_mat[i,j] = 1
					end
					length_mat[i,j] = largo_ij
				end
			end
			adj_mat = adj_mat .+ adj_mat'
			combi_predios = graphMod.node_combis(adj_mat)

		else
			adj_mat = 1
			combi_predios = [[1]]
		end
		
		length_combi_predios = length(combi_predios)
		display(length_combi_predios)
			
		vec_area_combi = zeros(length_combi_predios, 1)
		for i = 1:length_combi_predios
			combi_i = combi_predios[i]
			ps_i = polyShape.polyUnion(polyShape.subShape(ps_predios_manzana, combi_i))
			
			if ps_i.NumRegions == 1 #Si la unión genera un sólo polígono --> predios están conectados
				area_i = polyShape.polyArea(ps_i)
				vec_codigo_predial_i = df_predios_manzana.codigo_predial[combi_i]
				if area_i >= area_predio_lb && area_i <= area_predio_ub && length(combi_i) <= num_lote_max
					display("Largo Combi Predios: "*string(length(vec_codigo_predial_i)))
					vec_area_ps_i = polyShape.polyArea(polyShape.subShape(ps_predios_manzana, combi_i), sep_flag = true)
					area_max_lote = maximum(vec_area_ps_i)
					area_min_lote = minimum(vec_area_ps_i)
					vecColumnNames = ["combi_predios_str", "status", "num_lotes", "area_predio", "area_max_lote", "area_min_lote", "id"]
					vecColumnValue = [vec_codigo_predial_i, 0, length(combi_i), area_i, area_max_lote, area_min_lote, string(i)]
					pg_julia.insertRow!(conn_LandValue, "tabla_combinacion_predios", vecColumnNames, vecColumnValue, :id)
				end
			end
		end
	end

end

