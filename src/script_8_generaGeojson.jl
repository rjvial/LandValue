using LandValue, DotEnv

DotEnv.load("secrets.env")
datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]

conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])


display("Obtiene DatosCabidaArquitectura")
@time df_arquitectura = pg_julia.query(conn_LandValue, """SELECT * FROM public."tabla_arquitectura_default";""")
dca = DatosCabidaArquitectura()
for field_s in fieldnames(DatosCabidaArquitectura)
    value_ = df_arquitectura[:, field_s][1]
    setproperty!(dca, field_s, value_)
end
alturaPiso = dca.alturaPiso

# display("Obtiene listado de todas las combinaciones")
query_resultados_str = """
select id from tabla_resultados_cabidas ORDER BY id ASC;
"""
df_id = pg_julia.query(conn_LandValue, query_resultados_str)

numRows, numCols = size(df_id)
rowSet = df_id[:,"id"]

for r in rowSet

    try
        r_str = string(r)
        query_resultados_r = """
        select id, optimo_solucion, cabida_num_pisos, ps_predio, ps_base, "ps_primerPiso", "vec_psVolteor", dx, dy, gap_porcentual
        from tabla_resultados_cabidas where id = $r_str ORDER BY id ASC;
        """
        df_r = pg_julia.query(conn_LandValue, query_resultados_r)

        numPisos = df_r[1, "cabida_num_pisos"]
        xopt = eval(Meta.parse(df_r[1, "optimo_solucion"]))
        ps_predio = eval(Meta.parse(df_r[1, "ps_predio"]))
        ps_volTeorico = eval(Meta.parse(df_r[1, "vec_psVolteor"]))
        ps_base = eval(Meta.parse(df_r[1, "ps_base"]))
        ps_base_primerPiso = eval(Meta.parse(df_r[1, "ps_primerPiso"]))
        ps_areaEdif = deepcopy(ps_volTeorico[1])
        dx = df_r[1, "dx"]
        dy = df_r[1, "dy"]
        id = df_r[1, "id"]
        gap_porcentual = df_r[1, "gap_porcentual"]
        
        filestr = "C:/Users/rjvia/Documents/Land_engines_code/Julia/edificios_geojson/edificio_" * string(id) * "_vitacura.geojson"

        create_edificio_geojson(xopt, ps_predio, ps_base, ps_base_primerPiso, ps_areaEdif, alturaPiso, dx, dy, filestr, gap_porcentual)
        display("Se Generó Archivo GeoJson de Cabida N° = " * string(r))
        display("")
    
    catch
    end
end

