function opti_vol_edificio_sinsombra(vec_psVolteor, vec_altVolteor, vec_pisos, alturaPiso, max_ocupacion_suelo, maxConstruccionSNT, ps_areaEdif, K; ancho_crujia_min = ancho_crujia_min, ancho_crujia_max = ancho_crujia_max)

    vecLargoLados, _, _, _ = polyShape.extraeInfoPoly(ps_areaEdif)
    max_lado = maximum(vecLargoLados)
    alt_max   = maximum(vec_altVolteor)
    max_pisos = maximum(vec_pisos)
    min_pisos = ancho_crujia_max > 0 ? min(max_pisos-2, Int(floor(maxConstruccionSNT / (max_lado * ancho_crujia_max)))) : max_pisos - 2

    local ps_stack, np_stack

    # Storage for best known
    best_ps = [PolyShape([],1) for _ in 1:K]
    best_np = zeros(Int, K)

    max_sol = 0
    for pisos in min_pisos:max_pisos
        combos = generate_stack_vector(pisos, K)
        for c in combos
            ps_stack, np_stack, objective_val = opti_vol_edificio(vec_psVolteor, vec_altVolteor, c, alturaPiso, max_ocupacion_suelo, maxConstruccionSNT, K, ancho_crujia_min = ancho_crujia_min, ancho_crujia_max = ancho_crujia_max)
            if objective_val > max_sol
                # Store best
                max_sol = objective_val
                best_ps = deepcopy(ps_stack)
                best_np = deepcopy(np_stack)
            end
        end
    end

    return best_ps, best_np, max_sol
end