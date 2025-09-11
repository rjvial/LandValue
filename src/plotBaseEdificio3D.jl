################################################################################
#  HELPER FUNCTIONS
################################################################################

function plot_building_floors(vec_ps, vec_np, alturaPiso, color, alpha, fig, ax, ax_mat, is_underground=false)
    cum_floors = 0
    for i in eachindex(vec_ps)
        base = vec_ps[i]
        n_f = vec_np[i]
        for k in 1:(is_underground ? abs(n_f) : n_f)
            if is_underground
                z_low = -alturaPiso * (cum_floors + k)
                z_high = -alturaPiso * (cum_floors + k - 1)
            else
                z_low = alturaPiso * (cum_floors + k - 1)
                z_high = alturaPiso * (cum_floors + k)
            end
            V = base.Vertices[1]
            V_k = [V z_low*ones(size(V,1),1); V z_high*ones(size(V,1),1)]
            fig, ax, ax_mat = polyPlot.plotPolyshape2Din3D(PolyShape([V_k],1), z_low, color, alpha, fig=fig, ax=ax, ax_mat=ax_mat)
            fig, ax, ax_mat = polyPlot.plotPolyshape2Din3D(base, z_high, color, alpha, fig=fig, ax=ax, ax_mat=ax_mat)
        end
        cum_floors += (is_underground ? abs(n_f) : n_f)
    end
    return fig, ax, ax_mat
end

function plot_shadows_conditional(shadows, flags, color, alpha, fig, ax, ax_mat)
    for (shadow, flag) in zip(shadows, flags)
        if flag
            fig, ax, ax_mat = polyPlot.plotPolyshape2Din3D(shadow, 0, color, alpha, fig=fig, ax=ax, ax_mat=ax_mat)
        end
    end
    return fig, ax, ax_mat
end

function get_shadows_if_available(ps_pre_p, ps_pre_o, ps_pre_s, fallback_func, args...)
    if ps_pre_p !== nothing && ps_pre_o !== nothing && ps_pre_s !== nothing
        return ps_pre_p, ps_pre_o, ps_pre_s
    else
        return fallback_func(args...)
    end
end

################################################################################
#  MAIN PLOTTING FUNCTION (WITH CALCULATION)
################################################################################

function plotBaseEdificio3D(fpe, alturaPiso, ps_predio, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra, 
                            vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte, tipo_edificio, ps_publico, ps_calles)
    fig = nothing; ax = nothing; ax_mat = nothing

    # Plot predio
    if fpe.predio
        fig, ax, ax_mat = polyPlot.plotPolyshape2Din3D(ps_predio, 0.0, "green", 0.3, fig=fig, ax=ax, ax_mat=ax_mat)
    end

    # Plot building floors
    if fpe.edif
        color = (tipo_edificio == "departamento") ? "teal" : "darkgray"
        fig, ax, ax_mat = plot_building_floors(vec_ps_opt, vec_np_opt, alturaPiso, color, 1.0, fig, ax, ax_mat)
        fig, ax, ax_mat = plot_building_floors(vec_ps_subte, vec_np_subte, alturaPiso, "black", 0.2, fig, ax, ax_mat, true)
    end

    # Plot theoretical shadows
    if fpe.sombraVolTeorico_p || fpe.sombraVolTeorico_o || fpe.sombraVolTeorico_s
        ps_p, ps_o, ps_s = generaSombraTeor(vec_psVolteor, vec_altVolteor, ps_publico, ps_calles)
        fig, ax, ax_mat = plot_shadows_conditional([ps_p, ps_o, ps_s], [fpe.sombraVolTeorico_p, fpe.sombraVolTeorico_o, fpe.sombraVolTeorico_s], "gold", 0.3, fig, ax, ax_mat)
    end

    # Plot actual building shadows
    ps_p, ps_o, ps_s = generaSombraEdificio(vec_ps_opt, cumsum(vec_np_opt).*alturaPiso, ps_publico, ps_calles)
    for ps_sombra in [ps_p, ps_o, ps_s]
        fig, ax, ax_mat = polyPlot.plotPolyshape2Din3D(ps_sombra, 0, "red", 0.25, fig=fig, ax=ax, ax_mat=ax_mat)
    end

    # Plot volume outlines
    if fpe.volTeorico
        fig, ax, ax_mat = polyPlot.plotPolyshape2DVecin3D(vec_psVolteor, vec_altVolteor, "red", 0.001, fig=fig, ax=ax, ax_mat=ax_mat, edge_color="red", line_width=0.05)
    end
    if fpe.volConSombra
        fig, ax, ax_mat = polyPlot.plotPolyshape2DVecin3D(vec_psVolConSombra, vec_altVolConSombra, "gray", 0.01, fig=fig, ax=ax, ax_mat=ax_mat, edge_color="gray", line_width=0.1)
    end

    return fig, ax, ax_mat
end

################################################################################
#  MAIN PLOTTING FUNCTION (WITH PRE-CALCULATED SHADOWS)
################################################################################

function plotBaseEdificio3D(fpe, alturaPiso, ps_predio, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra, 
                            vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte, tipo_edificio, 
                            ps_sombraVolTeorico_p, ps_sombraVolTeorico_o, ps_sombraVolTeorico_s, 
                            ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s)
    fig = nothing; ax = nothing; ax_mat = nothing

    # Plot predio
    if fpe.predio
        fig, ax, ax_mat = polyPlot.plotPolyshape2Din3D(ps_predio, 0.0, "green", 0.3, fig=fig, ax=ax, ax_mat=ax_mat)
    end

    # Plot building floors
    if fpe.edif
        color = (tipo_edificio == "departamento") ? "teal" : "darkgray"
        fig, ax, ax_mat = plot_building_floors(vec_ps_opt, vec_np_opt, alturaPiso, color, 1.0, fig, ax, ax_mat)
        fig, ax, ax_mat = plot_building_floors(vec_ps_subte, vec_np_subte, alturaPiso, "black", 0.2, fig, ax, ax_mat, true)
    end

    # Plot theoretical shadows - use pre-calculated if available
    if fpe.sombraVolTeorico_p || fpe.sombraVolTeorico_o || fpe.sombraVolTeorico_s
        fig, ax, ax_mat = plot_shadows_conditional([ps_sombraVolTeorico_p, ps_sombraVolTeorico_o, ps_sombraVolTeorico_s], [fpe.sombraVolTeorico_p, fpe.sombraVolTeorico_o, fpe.sombraVolTeorico_s], "gold", 0.3, fig, ax, ax_mat)
    end

    # Plot actual building shadows - use pre-calculated if available
    for ps_sombra in [ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s]
        fig, ax, ax_mat = polyPlot.plotPolyshape2Din3D(ps_sombra, 0, "red", 0.25, fig=fig, ax=ax, ax_mat=ax_mat)
    end

    # Plot volume outlines
    if fpe.volTeorico
        fig, ax, ax_mat = polyPlot.plotPolyshape2DVecin3D(vec_psVolteor, vec_altVolteor, "red", 0.001, fig=fig, ax=ax, ax_mat=ax_mat, edge_color="red", line_width=0.05)
    end
    if fpe.volConSombra
        fig, ax, ax_mat = polyPlot.plotPolyshape2DVecin3D(vec_psVolConSombra, vec_altVolConSombra, "gray", 0.01, fig=fig, ax=ax, ax_mat=ax_mat, edge_color="gray", line_width=0.1)
    end

    return fig, ax, ax_mat
end

################################################################################
#  CONVENIENCE WRAPPER (WITH DICTIONARY)
################################################################################

function plotBaseEdificio3D(fpe, alturaPiso, ps_predio, dict_resultado)
    ps_sombraVolTeorico_p = get(dict_resultado, "ps_sombraVolTeorico_p", nothing)
    ps_sombraVolTeorico_o = get(dict_resultado, "ps_sombraVolTeorico_o", nothing)
    ps_sombraVolTeorico_s = get(dict_resultado, "ps_sombraVolTeorico_s", nothing)
    ps_sombraEdif_p = get(dict_resultado, "ps_sombraEdif_p", nothing)
    ps_sombraEdif_o = get(dict_resultado, "ps_sombraEdif_o", nothing)
    ps_sombraEdif_s = get(dict_resultado, "ps_sombraEdif_s", nothing)
    
    return plotBaseEdificio3D(
        fpe, alturaPiso, ps_predio,
        dict_resultado["vec_psVolteor"], dict_resultado["vec_altVolteor"],
        dict_resultado["vec_psVolConSombra"], dict_resultado["vec_altVolConSombra"],
        dict_resultado["vec_ps_opt"], dict_resultado["vec_np_opt"],
        dict_resultado["vec_ps_subte"], dict_resultado["vec_np_subte"],
        dict_resultado["tipo_edificio"],
        ps_sombraVolTeorico_p, ps_sombraVolTeorico_o, ps_sombraVolTeorico_s,
        ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s
    )
end