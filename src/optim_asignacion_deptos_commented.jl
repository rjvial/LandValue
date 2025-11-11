using JuMP
using Cbc

"""
    optim_asignacion_deptos(W, H, num_strips, set_i, set_w, mat_w, vec_h, vec_a, mat_p, mat_pc, mat_pcc, min_deptos, max_deptos)

Optimiza la asignación de departamentos en strips horizontales para maximizar superficie total.

# Argumentos
- `W::Float64`: Ancho del edificio (m)
- `H::Float64`: Altura total del edificio (m)
- `num_strips::Int`: Número de strips horizontales
- `set_i::Vector{Int}`: Conjunto de índices de tipos de departamentos
- `set_w::Vector{Int}`: Conjunto de índices de alturas
- `mat_w`: Matriz de anchos [h,i] por tipo de departamento
- `vec_h`: Vector de alturas por índice h
- `vec_a`: Vector de áreas por tipo i
- `mat_p, mat_pc, mat_pcc`: Matrices de perímetros (regular, corner, corner2)
- `min_deptos::Int`: Número mínimo de departamentos
- `max_deptos::Int`: Número máximo de departamentos

# Tipos de departamentos
- `z`: Departamentos regulares
- `z_c`: Departamentos en esquina (corner) - siempre 2 por strip si se usan
- `z_cc`: Departamentos en esquina doble (corner2) - máximo 1 por strip

# Returns
- `Dict{String,Any}`: Diccionario con resultados de optimización
"""
function optim_asignacion_deptos(
    W::Float64,
    H::Float64,
    num_strips::Int,
    set_i::Vector{Int},
    set_w::Vector{Int},
    mat_w,
    vec_h,
    vec_a,
    mat_p, mat_pc, mat_pcc,
    min_deptos::Int,
    max_deptos::Int)

    A = H*W

    model = Model(Cbc.Optimizer)
    set_optimizer_attribute(model, "logLevel", 1)
    set_optimizer_attribute(model, "seconds", 300)

    S = 1:num_strips

    @variables(model, begin
        0 <= z[s in S, i in set_i, h in set_w] <= max_deptos, Int
        0 <= z_c[s in S, i in set_i, h in set_w] <= max_deptos, Int
        0 <= z_cc[s in S, i in set_i, h in set_w] <= max_deptos, Int
        x[s in S, i in set_i, h in set_w], Bin
        x_c[s in S, i in set_i, h in set_w], Bin
        x_cc[s in S, i in set_i, h in set_w], Bin
        H_s[s in S] >= 0
        y_c[s in S], Bin
        y_cc[s in S], Bin
    end)

    @constraint(model, constraint_uso_strip_c[s in S],
        sum(z_c[s,i,h] for i in set_i, h in set_w) == 2 * y_c[s]
    )

    @constraint(model, constraint_uso_strip_cc[s in S],
        sum(z_cc[s,i,h] for i in set_i, h in set_w) == y_cc[s]
    )

    @constraint(model, constraint_y_cc[s in S],
        sum(x_cc[s,i,h] + x[s,i,h] for i in set_i, h in set_w) <= y_cc[s] + (1 - y_cc[s]) * max_deptos
    )

    @constraint(model, constraint_corner_c_o_cc[s in S],
        y_c[s] + y_cc[s] <= 1
    )

    @expression(model, deptos_total,
        sum(z[s,i,h] for s in S, i in set_i, h in set_w) +
        sum(z_c[s,i,h] for s in S, i in set_i, h in set_w) +
        sum(z_cc[s,i,h] for s in S, i in set_i, h in set_w)
    )

    @constraint(model, constraint_min_max_deptos,
        min_deptos <= deptos_total <= max_deptos
    )

    @constraint(model, constraint_suma_profundidades,
        sum(H_s[s] for s in S) <= H
    )

    @constraint(model, constraint_profundidad_strip[s in S],
        H_s[s] >= 8.0
    )

    @constraints(model, begin
        constraint_profundidad_strip_z[s in S, i in set_i, h in set_w], x[s,i,h] * vec_h[h] <= H_s[s]
        constraint_profundidad_strip_z_c[s in S, i in set_i, h in set_w], x_c[s,i,h] * vec_h[h] <= H_s[s]
        constraint_profundidad_strip_z_cc[s in S, i in set_i, h in set_w], x_cc[s,i,h] * vec_h[h] <= H_s[s]
    end)

    @expression(model, sup_deptos_total,
        sum((z[s,i,h] + z_c[s,i,h] + z_cc[s,i,h]) * vec_a[i] for s in S, i in set_i, h in set_w)
    )

    @constraint(model, constraint_area_total, sup_deptos_total <= A)

    @constraint(model, constraint_area_strip[s in S],
        sum((z[s,i,h] + z_c[s,i,h] + z_cc[s,i,h]) * vec_a[i] for i in set_i, h in set_w) <= W * H_s[s]
    )

    @constraints(model, begin
        constraint_big_m_z[s in S, i in set_i, h in set_w], z[s,i,h] <= max_deptos * x[s,i,h]
        constraint_big_m_z_c[s in S, i in set_i, h in set_w], z_c[s,i,h] <= max_deptos * x_c[s,i,h]
        constraint_big_m_z_cc[s in S, i in set_i, h in set_w], z_cc[s,i,h] <= max_deptos * x_cc[s,i,h]
    end)

    @constraint(model, constraint_ancho_strip[s in S],
        sum((z[s,i,h] + z_c[s,i,h] + z_cc[s,i,h]) * mat_w[h,i] for i in set_i, h in set_w) <= W
    )

    @constraint(model, constraint_perimetro[s in S],
        sum(z[s,i,h] * mat_p[h,i] for i in set_i, h in set_w) +
        sum(z_c[s,i,h] * mat_pc[h,i] for i in set_i, h in set_w) +
        sum(z_cc[s,i,h] * mat_pcc[h,i] for i in set_i, h in set_w) >= 2*H_s[s] + W - 1
    )

    @objective(model, Max, sup_deptos_total)

    optimize!(model)

    results = Dict{String,Any}()
    results["status"] = termination_status(model)
    results["solve_time"] = solve_time(model)
    results["z"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["z_c"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["z_cc"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["x"] = Dict{Tuple{Int,Int,Int},Int}()
    results["x_c"] = Dict{Tuple{Int,Int,Int},Int}()
    results["x_cc"] = Dict{Tuple{Int,Int,Int},Int}()
    results["H_s"] = Dict{Int,Float64}()
    results["perimetro_strip"] = Dict{Int,Float64}()

    if has_values(model)
        results["objective_value"] = objective_value(model)

        for s in S
            results["H_s"][s] = value(H_s[s])

            perimetro_s = sum(value(z[s,i,h]) * mat_p[h,i] for i in set_i, h in set_w) +
                          sum(value(z_c[s,i,h]) * mat_pc[h,i] for i in set_i, h in set_w) +
                          sum(value(z_cc[s,i,h]) * mat_pcc[h,i] for i in set_i, h in set_w)
            results["perimetro_strip"][s] = perimetro_s

            for i in set_i, h in set_w
                for (var, key, threshold, is_binary) in [
                    (z[s,i,h], "z", 0.001, false),
                    (z_c[s,i,h], "z_c", 0.001, false),
                    (z_cc[s,i,h], "z_cc", 0.001, false),
                    (x[s,i,h], "x", 0.5, true),
                    (x_c[s,i,h], "x_c", 0.5, true),
                    (x_cc[s,i,h], "x_cc", 0.5, true)]

                    val = value(var)
                    if val > threshold
                        results[key][(s,i,h)] = is_binary ? 1 : val
                    end
                end
            end
        end

        results["total_deptos"] = sum(sum(values(results[k])) for k in ["z", "z_c", "z_cc"])
    else
        results["objective_value"] = nothing
        results["total_deptos"] = 0.0
        println("\n⚠️  WARNING: No feasible solution found!")
        println("Status: $(results["status"])")
    end

    return results
end

function print_results(results::Dict)
    println("\n" * "="^60)
    println("RESULTADOS OPTIMIZACIÓN ASIGNACIÓN DEPTOS")
    println("="^60)
    println("Estado: $(results["status"])")

    if isnothing(results["objective_value"])
        println("Valor objetivo: N/A (sin solución factible)")
    else
        println("Valor objetivo: $(round(results["objective_value"], digits=2))")
    end

    println("Tiempo de solución: $(round(results["solve_time"], digits=2)) segundos")
    println("Total departamentos: $(round(results["total_deptos"], digits=0))")
    println("\n" * "-"^60)
    println("ASIGNACIÓN POR STRIP:")
    println("-"^60)

    for (strip, profundidad) in sort(collect(results["H_s"]))
        perimetro = get(results["perimetro_strip"], strip, 0.0)
        println("\nStrip $strip - profundidad: $(round(profundidad, digits=2)) m - Perímetro: $(round(perimetro, digits=2)) m")

        for (key, label) in [("z", "regulares"), ("z_c", "corner"), ("z_cc", "corner 2")]
            strip_deptos = filter(p -> p[1][1] == strip, collect(results[key]))
            if !isempty(strip_deptos)
                println("  Deptos $label:")
                for ((s, i, h), count) in strip_deptos
                    println("    Tipo ($i,$h): $(round(count, digits=0)) unidades")
                end
            end
        end
    end
    println("\n" * "="^60)
end
