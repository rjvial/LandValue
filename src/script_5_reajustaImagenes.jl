using LandValue, Images, ImageBinarization, DotEnv

DotEnv.load("secrets.env") #Caso Docker
# datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
datos_LandValue = ["landengines_local", "postgres", "", "localhost"]

conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])


query_resultados_str = """
SELECT id
FROM public.tabla_resultados_cabidas
"""
df_resultados = pg_julia.query(conn_LandValue, query_resultados_str)

rowSet = sort(df_resultados[:,"id"])


for k in rowSet

    infileStr = "C:\\Users\\rjvia\\Documents\\Land_engines_code\\Julia\\imagenes_cabidas\\____cabida_vitacura_" * string(k) * ".png"
    outfileStr = "C:\\Users\\rjvia\\Documents\\Land_engines_code\\Julia\\imagenes_cabidas\\cabida_vitacura_" * string(k) * ".png"

    display(infileStr)

    try

        img = load(infileStr)

        img_bn = binarize(Gray.(img), UnimodalRosin()) .< 0.5

        pos_vec = []

        vec_bn_h = sum(img_bn * 1, dims=1)
        for i = 1:length(vec_bn_h)-1
            if (vec_bn_h[i] == 0) && (vec_bn_h[i+1] >= 1) && (length(pos_vec) < 1)
                pos_vec = push!(pos_vec, i)
            end
        end
        for i = length(vec_bn_h):-1:2
            if (vec_bn_h[i] == 0) && (vec_bn_h[i-1] >= 1) && (length(pos_vec) < 2)
                pos_vec = push!(pos_vec, i)
            end
        end

        vec_bn_v = sum(img_bn * 1, dims=2)
        for i = 1:length(vec_bn_v)-1
            if (vec_bn_v[i] == 0) && (vec_bn_v[i+1] >= 1) && (length(pos_vec) < 3)
                pos_vec = push!(pos_vec, i)
            end
        end
        for i = length(vec_bn_v):-1:2
            if (vec_bn_v[i] == 0) && (vec_bn_v[i-1] >= 1) && (length(pos_vec) < 4)
                pos_vec = push!(pos_vec, i)
            end
        end

        img_cropped = img[pos_vec[3]:pos_vec[4], pos_vec[1]:pos_vec[2]]
        save(outfileStr, img_cropped)

        rm(infileStr)
    catch
    end


end