using LandValue, DataFrames, DotEnv

DotEnv.load("secrets.env") #Caso Docker
datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
datos_mygis_db = ["gis_data", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
conn_gis_data = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])

infileStr = "C:\\Users\\rjvia\\Documents\\Land_engines_code\\Julia\\Valorizacion_Casas_Modelo_Comps.csv"
df_propiedades = pg_julia.csv2df(infileStr)

df_propiedades = df_propiedades[:, [:Rol, :Latitud, :Longitud, :Area_Homogenea, :Codigo_Comuna, :Manzana, :Predio, :Direccion, :Precio_Estimado_Final]]

numRows_propiedades, numCols_propiedades = size(df_propiedades)

query_str = """ 
CREATE TABLE IF NOT EXISTS public.tabla_propiedades
(
    "Rol" bigint, 
    "Latitud" double precision, 
    "Longitud" double precision, 
    "Area_Homogenea" text, 
    "Codigo_Comuna" int, 
    "Manzana" int, 
    "Predio" int, 
    "Direccion" text, 
    "Precio_Estimado_Final" double precision
)
"""
pg_julia.query(conn_LandValue, query_str)

pg_julia.appendToTable!(conn_LandValue, "tabla_propiedades", df_propiedades, :Rol)

