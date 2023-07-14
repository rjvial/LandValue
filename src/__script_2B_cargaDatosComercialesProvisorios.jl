using LandValue, DataFrames

conn_LandValue = pg_julia.connection("LandValue", "postgres", "postgres")

infileStr = "C:\\Users\\rjvia\\.julia\\dev\\qgis_env\\aux_files\\tabla_comercial_basica.csv"
df_tipos = pg_julia.csv2df(infileStr)

df_combiPredio = pg_julia.query(conn_LandValue, """SELECT * FROM public."tabla_combinacion_predios";""")



# df_sub = df[:, [:N_Edificio, :tipoUnidad, :supDeptoUtil, :supInterior, :supTerraza, :estacionamientosPorViv, :bodegasPorViv, 
#  :Precio_Estimado ]]


df_aux = DataFrame([[],[],[],[],[],[],[],[],[],[]], 
                ["id", "N_Edificio", "tipoUnidad", "codigo_predial", "supDeptoUtil", "supInterior", "supTerraza", "estacionamientosPorViv", "bodegasPorViv", "Precio_Estimado"])

query_str = """ 
CREATE TABLE IF NOT EXISTS public.tabla_cabida_comercial
(
    "id" int,
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

numCombinaciones = size(df_combiPredio,1)
numTipos = size(df_tipos,1)

for (i, row_combiPredios) in enumerate(eachrow(df_combiPredio))
    display(i)
    for (j, row_tipos) in enumerate(eachrow(df_tipos))
        cont = (i-1)*numTipos + j
        vecColumnNames = ["id", "N_Edificio", "tipoUnidad",           "codigo_predial",                     "supDeptoUtil",           "supInterior",           "supTerraza",           "estacionamientosPorViv",           "bodegasPorViv",           "Precio_Estimado"]
        vecColumnValue = [cont, i,            row_tipos[:tipoUnidad], "\""*row_combiPredios[:combi_predios_str]*"\"", row_tipos[:supDeptoUtil], row_tipos[:supInterior], row_tipos[:supTerraza], row_tipos[:estacionamientosPorViv], row_tipos[:bodegasPorViv], row_tipos[:Precio_Estimado]]
        push!(df_aux, vecColumnValue)
        # pg_julia.insertRow!(conn_LandValue, "tabla_cabida_comercial", vecColumnNames, vecColumnValue, :id)
    end
end

pg_julia.appendToTable!(conn_LandValue, "tabla_cabida_comercial", df_aux, :id)
