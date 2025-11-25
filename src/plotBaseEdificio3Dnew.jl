################################################################################
#  HELPER FUNCTIONS
################################################################################

function get_color_for_type(tipo_idx)
    colors = ["red", "blue", "orange", "purple", "cyan", "magenta", "yellow", "pink", "brown", "lime"]
    return colors[((tipo_idx - 1) % length(colors)) + 1]
end

function plot_building_floors_new(vec_ps, vec_np, alturaPiso, color, alpha, fig, ax, ax_mat, is_underground=false)
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

function plot_apartments_floor_new(vec_ps_deptos, z_low, z_high, color, alpha, fig, ax, ax_mat)
    for ps_depto in vec_ps_deptos
        if polyShape.polyArea(ps_depto) > 0.0
            V = ps_depto.Vertices[1]
            V_k = [V z_low*ones(size(V,1),1); V z_high*ones(size(V,1),1)]
            fig, ax, ax_mat = polyPlot.plotPolyshape2Din3D(PolyShape([V_k],1), z_low, color, alpha, fig=fig, ax=ax, ax_mat=ax_mat)
            fig, ax, ax_mat = polyPlot.plotPolyshape2Din3D(ps_depto, z_high, color, alpha, fig=fig, ax=ax, ax_mat=ax_mat)
        end
    end
    return fig, ax, ax_mat
end

function plot_unified_apartments_floor(ps_unified, z_low, z_high, color, alpha, fig, ax, ax_mat)
    if !isnothing(ps_unified) && polyShape.polyArea(ps_unified) > 0.0
        for k in 1:ps_unified.NumRegions
            V = ps_unified.Vertices[k]
            V_k = [V z_low*ones(size(V,1),1); V z_high*ones(size(V,1),1)]
            fig, ax, ax_mat = polyPlot.plotPolyshape2Din3D(PolyShape([V_k],1), z_low, color, alpha, fig=fig, ax=ax, ax_mat=ax_mat)
        end
        fig, ax, ax_mat = polyPlot.plotPolyshape2Din3D(ps_unified, z_high, color, alpha, fig=fig, ax=ax, ax_mat=ax_mat)
    end
    return fig, ax, ax_mat
end

function plot_common_area_new(ps_area, z_low, z_high, color, alpha, fig, ax, ax_mat)
    if !isnothing(ps_area) && polyShape.polyArea(ps_area) > 0.0
        for k in 1:ps_area.NumRegions
            V = ps_area.Vertices[k]
            V_k = [V z_low*ones(size(V,1),1); V z_high*ones(size(V,1),1)]
            fig, ax, ax_mat = polyPlot.plotPolyshape2Din3D(PolyShape([V_k],1), z_low, color, alpha, fig=fig, ax=ax, ax_mat=ax_mat)
        end
        fig, ax, ax_mat = polyPlot.plotPolyshape2Din3D(ps_area, z_high, color, alpha, fig=fig, ax=ax, ax_mat=ax_mat)
    end
    return fig, ax, ax_mat
end

function plot_shadows_conditional_new(shadows, flags, color, alpha, fig, ax, ax_mat)
    for (shadow, flag) in zip(shadows, flags)
        if flag
            fig, ax, ax_mat = polyPlot.plotPolyshape2Din3D(shadow, 0, color, alpha, fig=fig, ax=ax, ax_mat=ax_mat)
        end
    end
    return fig, ax, ax_mat
end


################################################################################
#  MAIN PLOTTING FUNCTION
################################################################################

function plotBaseEdificio3Dnew(fpe, alturaPiso, ps_predio, dict_resultado, results_primer_piso, results_pisos_superiores, num_pisos_superiores)
    fig = nothing; ax = nothing; ax_mat = nothing

    if fpe.predio
        fig, ax, ax_mat = polyPlot.plotPolyshape2Din3D(ps_predio, 0.0, "green", 0.3, fig=fig, ax=ax, ax_mat=ax_mat)
    end

    if fpe.edif
        ps_pasillo = results_pisos_superiores["ps_pasillo"]
        ps_area_comun_total_primer_piso = results_primer_piso["ps_area_comun_total"]

        ps_union_deptos_primer = results_primer_piso["ps_union_deptos"]
        ps_union_terrazas_primer = results_primer_piso["ps_union_terrazas"]

        fig, ax, ax_mat = plot_common_area_new(ps_area_comun_total_primer_piso, 0.0, alturaPiso, "#303030", 0.9, fig, ax, ax_mat)
        fig, ax, ax_mat = plot_unified_apartments_floor(ps_union_deptos_primer, 0.0, alturaPiso, "teal", 1.0, fig, ax, ax_mat)
        fig, ax, ax_mat = plot_unified_apartments_floor(ps_union_terrazas_primer, 0.0, 1.0, "#2F4F4F", 1.0, fig, ax, ax_mat)

        ps_union_deptos_sup = results_pisos_superiores["ps_union_deptos"]
        ps_union_terrazas_sup = results_pisos_superiores["ps_union_terrazas"]

        for piso in 1:num_pisos_superiores
            z_low = alturaPiso * piso
            z_high = alturaPiso * (piso + 1)
            fig, ax, ax_mat = plot_unified_apartments_floor(ps_union_deptos_sup, z_low, z_high, "teal", 1.0, fig, ax, ax_mat)
            fig, ax, ax_mat = plot_unified_apartments_floor(ps_union_terrazas_sup, z_low, z_low + 1.0, "#2F4F4F", 1.0, fig, ax, ax_mat)
            fig, ax, ax_mat = plot_common_area_new(ps_pasillo, z_low, z_high, "#303030", 0.6, fig, ax, ax_mat)
        end

        vec_ps_subte = dict_resultado["proyecto_vec_ps_subte"]
        vec_np_subte = dict_resultado["proyecto_vec_np_subte"]
        fig, ax, ax_mat = plot_building_floors_new(vec_ps_subte, vec_np_subte, alturaPiso, "black", 0.2, fig, ax, ax_mat, true)
    end

    ps_sombraVolTeorico_p = get(dict_resultado, "proyecto_ps_sombraVolTeorico_p", nothing)
    ps_sombraVolTeorico_o = get(dict_resultado, "proyecto_ps_sombraVolTeorico_o", nothing)
    ps_sombraVolTeorico_s = get(dict_resultado, "proyecto_ps_sombraVolTeorico_s", nothing)

    if fpe.sombraVolTeorico_p || fpe.sombraVolTeorico_o || fpe.sombraVolTeorico_s
        fig, ax, ax_mat = plot_shadows_conditional_new([ps_sombraVolTeorico_p, ps_sombraVolTeorico_o, ps_sombraVolTeorico_s],
                                                     [fpe.sombraVolTeorico_p, fpe.sombraVolTeorico_o, fpe.sombraVolTeorico_s],
                                                     "gold", 0.3, fig, ax, ax_mat)
    end

    ps_sombraEdif_p = get(dict_resultado, "proyecto_ps_sombraEdif_p", nothing)
    ps_sombraEdif_o = get(dict_resultado, "proyecto_ps_sombraEdif_o", nothing)
    ps_sombraEdif_s = get(dict_resultado, "proyecto_ps_sombraEdif_s", nothing)

    for ps_sombra in [ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s]
        if !isnothing(ps_sombra)
            fig, ax, ax_mat = polyPlot.plotPolyshape2Din3D(ps_sombra, 0, "red", 0.25, fig=fig, ax=ax, ax_mat=ax_mat)
        end
    end

    if fpe.volTeorico
        vec_psVolteor = dict_resultado["proyecto_vec_psVolteor"]
        vec_altVolteor = dict_resultado["proyecto_vec_altVolteor"]
        fig, ax, ax_mat = polyPlot.plotPolyshape2DVecin3D(vec_psVolteor, vec_altVolteor, "red", 0.001, fig=fig, ax=ax, ax_mat=ax_mat, edge_color="red", line_width=0.05)
    end

    if fpe.volConSombra
        vec_psVolConSombra = dict_resultado["proyecto_vec_psVolConSombra"]
        vec_altVolConSombra = dict_resultado["proyecto_vec_altVolConSombra"]
        fig, ax, ax_mat = polyPlot.plotPolyshape2DVecin3D(vec_psVolConSombra, vec_altVolConSombra, "gray", 0.01, fig=fig, ax=ax, ax_mat=ax_mat, edge_color="gray", line_width=0.1)
    end

    if !isnothing(ax)
        current_xlim = ax.get_xlim()
        current_ylim = ax.get_ylim()
        current_zlim = ax.get_zlim()

        x_center = (current_xlim[1] + current_xlim[2]) / 2
        y_center = (current_ylim[1] + current_ylim[2]) / 2
        z_center = (current_zlim[1] + current_zlim[2]) / 2

        x_range = current_xlim[2] - current_xlim[1]
        y_range = current_ylim[2] - current_ylim[1]
        z_range = current_zlim[2] - current_zlim[1]

        zoom_factor = 0.6

        new_x_range = x_range * zoom_factor
        new_y_range = y_range * zoom_factor
        new_z_range = z_range * zoom_factor

        ax.set_xlim(x_center - new_x_range/2, x_center + new_x_range/2)
        ax.set_ylim(y_center - new_y_range/2, y_center + new_y_range/2)
        ax.set_zlim(max(0, z_center - new_z_range/2), z_center + new_z_range/2)

        ax.xaxis.pane.fill = false
        ax.yaxis.pane.fill = false
        ax.zaxis.pane.fill = false
        ax.xaxis.pane.set_edgecolor("white")
        ax.yaxis.pane.set_edgecolor("white")
        ax.zaxis.pane.set_edgecolor("white")
        ax.grid(false)
    end

    return fig, ax, ax_mat
end
