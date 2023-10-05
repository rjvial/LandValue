using CSV, DataFrames, JuMP, Cbc

function contiene_str(str, vec)
    vec_occ = occursin.(str, vec)
    num_occ = sum(vec_occ)
    return vec_occ, num_occ
end

function genera_tri_vec(vec, min_frec)
    letras = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "X", "Y", "Z"]
    vec_tri = []
    mat_vec = []
    flag = true
    for i in letras
        display(i)
        for j in letras
            for k in letras
                tri = i * j * k
                vec_occ, num_occ = contiene_str(tri, vec)
                if num_occ > min_frec
                    push!(vec_tri, tri)
                    if flag
                        mat_vec = vec_occ
                        flag = false
                    else
                        mat_vec = [mat_vec vec_occ]
                    end
                end
            end
        end
    end
    mat_vec = mat_vec .* 1 
    return vec_tri, mat_vec
end

df = DataFrame(CSV.File("src\\nombres_cbrs\\nombres.csv"))

vec = df[df[:, "frec_pri"] .>= 200, "apellido"]
vec_tri, mat_vec = genera_tri_vec(vec, 200)

num_vec = sum(mat_vec, dims=2)
num_vec = reshape(num_vec, :)

mat_vec = mat_vec[num_vec .>= 1, :]


num_row, num_col = size(mat_vec)

m = JuMP.Model(Cbc.Optimizer)
JuMP.set_optimizer_attribute(m, "ratioGap", 0.001)
set_optimizer_attribute(m, "logLevel", 0)

@variables(m, begin
    x[u = 1:length(vec_tri)], Bin # Es 1 si el tipoDepto se utiliza, 0 en caso contrario 
end)

@constraints(m, begin
# Restricción de Densidad
    mat_vec * x .>= 1
end)

@objective(m, Min, sum(x) )
JuMP.optimize!(m)

xopt = JuMP.value.(x)

sum(xopt)
