using LandValue, DataFrames, DotEnv 

DotEnv.load("secrets.env") #Caso Docker
datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
# datos_LandValue = ["landengines_local", "postgres", "", "localhost"]

conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])



# infileStr = "C:\\Users\\rjvia\\.julia\\dev\\qgis_env\\aux_files\\Salida_RF_Log.csv"
infileStr = "C:\\Users\\rjvia\\Documents\\Land_engines_code\\Julia\\Salida_RF_Log.csv"
df = pg_julia.csv2df(infileStr)

df_sub = df[:, [:N_Edificio, :tipoUnidad, :supDeptoUtil, :supInterior, :supTerraza, :estacionamientosPorViv, :bodegasPorViv, 
 :Precio_Estimado ]]

df_cp = df[:, [:codigo_predial_1, :codigo_predial_2, :codigo_predial_3, :codigo_predial_4, :codigo_predial_5, :codigo_predial_6, :codigo_predial_7, :codigo_predial_8, :codigo_predial_9, :codigo_predial_10, :codigo_predial_11, :codigo_predial_12]]

cp_1 =  string.(df_cp[!,"codigo_predial_1"])
cp_2 =  replace(df_cp[!,"codigo_predial_2"], "NA" => "_")
cp_3 =  replace(df_cp[!,"codigo_predial_3"], "NA" => "_")
cp_4 =  replace(df_cp[!,"codigo_predial_4"], "NA" => "_")
cp_5 =  replace(df_cp[!,"codigo_predial_5"], "NA" => "_")
cp_6 =  replace(df_cp[!,"codigo_predial_6"], "NA" => "_")
cp_7 =  replace(df_cp[!,"codigo_predial_7"], "NA" => "_")
cp_8 =  replace(df_cp[!,"codigo_predial_8"], "NA" => "_")
cp_9 =  replace(df_cp[!,"codigo_predial_9"], "NA" => "_")
cp_10 = replace(df_cp[!,"codigo_predial_10"], "NA" => "_")
cp_11 = replace(df_cp[!,"codigo_predial_11"], "NA" => "_")
cp_12 = replace(df_cp[!,"codigo_predial_12"], "NA" => "_")

numRows = length(cp_1)
list_codigoCombi = fill("",numRows)
for i = 1:numRows
    cp_i = "\"[" * string(cp_1[i]) * ", " * string(cp_2[i])  * ", " * string(cp_3[i])  * ", " * string(cp_4[i]) * ", " * 
                   string(cp_5[i]) * ", " * string(cp_6[i])  * ", " * string(cp_7[i])  * ", " * string(cp_8[i]) * ", " *
                   string(cp_9[i]) * ", " * string(cp_10[i]) * ", " * string(cp_11[i]) * ", " * string(cp_12[i]) * "]\""
    cp_i = replace(cp_i, ", _" => "")
    # cp_i = replace(cp_i, ", .0" => "")
    # cp_i = replace(cp_i, ".0" => "")

    list_codigoCombi[i] = cp_i
end

DataFrames.insertcols!(df_sub, 3, :codigo_predial => list_codigoCombi)



query_str = """ 
CREATE TABLE IF NOT EXISTS public.tabla_cabida_comercial
(
    "N_Edificio" int,
    "tipoUnidad" text,
    "codigo_predial" text,
    "supDeptoUtil" double precision,
    "supInterior" double precision,
    "supTerraza" double precision,
    "estacionamientosPorViv" double precision,
    "bodegasPorViv" double precision,
    "Precio_Estimado" double precision
)
"""
pg_julia.query(conn_LandValue, query_str)

pg_julia.appendToTable!(conn_LandValue, "tabla_cabida_comercial", df_sub, :id)
