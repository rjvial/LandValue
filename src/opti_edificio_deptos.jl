function opti_edificio_deptos(dict_arquitectura, max_ocupacion_suelo, max_constructibilidad, max_deptos, vec_ps_opt, vec_np_opt, flag_dfl2, sup_patio_vivienda_economica)

    # Base areas
    K = length(vec_ps_opt) # num stacks
    vec_areaBasal = [polyShape.polyArea(ps) for ps in vec_ps_opt]


    num_pisos = sum(vec_np_opt)
    num_pisos_regulares = num_pisos - 1 # Pisos regulares (sin primer piso)


    # Variants and area matrices
    numTipos = length(dict_arquitectura["vecSupUtil"])
    vecSupUtil    = dict_arquitectura["vecSupUtil"]
    vecSupTerraza = dict_arquitectura["vecSupTerraza"]
    vecSupInterior= dict_arquitectura["vecSupInterior"]

    vec_dfl_2 = [vecSupUtil[i] <= 140 ? 1 : 0 for i in 1:numTipos]

    # Total built footprint (for common areas minimums)
    supEdifTotal = sum(vec_areaBasal[i] * vec_np_opt[i] for i in 1:K)

    # Build JuMP model
    m = Model(Cbc.Optimizer)
    set_optimizer_attribute(m, "ratioGap", 0.001)
    set_optimizer_attribute(m, "logLevel", 0)

    @variables(m, begin
        # choose at most one variant per type
        numDeptosPrimerPiso[u=1:numTipos] >= 0, Int
        numDeptosPorPisoSup[u=1:numTipos] >= 0, Int
        supComunPrimerPiso >= 0
        supComunPisosSup   >= 0
        descuento_dfl2     >= 0
    end)

    # expressions
    @expression(m, supComun, supComunPrimerPiso + supComunPisosSup)

    @expression(m, supUtilPrimerPiso,    sum(vecSupUtil[u]    * numDeptosPrimerPiso[u] for u=1:numTipos))
    @expression(m, supUtilPisosSup,      sum(vecSupUtil[u]    * numDeptosPorPisoSup[u] * num_pisos_regulares for u=1:numTipos))
    @expression(m, supUtil, supUtilPrimerPiso + supUtilPisosSup)

    @expression(m, supTerrazaPrimerPiso, sum(vecSupTerraza[u] * numDeptosPrimerPiso[u] for u=1:numTipos))
    @expression(m, supTerrazaPisosSup,   sum(vecSupTerraza[u] * numDeptosPorPisoSup[u] * num_pisos_regulares for u=1:numTipos))
    @expression(m, supTerraza, supTerrazaPrimerPiso + supTerrazaPisosSup)

    @expression(m, supInteriorPrimerPiso,sum(vecSupInterior[u]* numDeptosPrimerPiso[u] for u=1:numTipos))
    @expression(m, supInteriorPisosSup,  sum(vecSupInterior[u]* numDeptosPorPisoSup[u] * num_pisos_regulares for u=1:numTipos))
    @expression(m, supInterior, supInteriorPrimerPiso + supInteriorPisosSup)

    @expression(m, numDeptos,   numDeptosPrimerPiso + numDeptosPorPisoSup * num_pisos_regulares)

    # constraints
    @constraints(m, begin

        # Max densidad 
        sum(numDeptos) <= max_deptos
        
        # restricciones de area comun
        descuento_dfl2 <= flag_dfl2 * 0.2 * supUtil 
        descuento_dfl2 <= flag_dfl2 * supComun
        supComunPrimerPiso >= dict_arquitectura["coefSupComunPrimerPiso"] * vec_areaBasal[1] #minSupComunPrimerPiso
        supComunPisosSup   >= dict_arquitectura["coefSupComunPisosSup"] * supUtil  #minSupComunPisosSup
        # supComun   >= 0.15 * supUtil

        # balance de superficie por piso 
        supComunPrimerPiso + supTerrazaPrimerPiso + supInteriorPrimerPiso <= vec_areaBasal[1]
        supComunPisosSup + supTerrazaPisosSup + supInteriorPisosSup <= sum(vec_areaBasal[k] * (k==1 ? vec_np_opt[k]-1 : vec_np_opt[k]) for k=1:K)

        supComunPrimerPiso + supTerrazaPrimerPiso + supInteriorPrimerPiso <= max_ocupacion_suelo - sum(numDeptos) * sup_patio_vivienda_economica 

        # Max constructibilidad
        supUtil + supComun - descuento_dfl2 <= max_constructibilidad

    end)

    # numDeptos > 0 solo si se elije la variante y tipo correspondiente
    if flag_dfl2 || sup_patio_vivienda_economica > 0
        @constraint(m, [u=1:numTipos], numDeptos[u] <= vec_dfl_2[u] * max_deptos)
    else
        @constraint(m, [u=1:numTipos], numDeptos[u] <= max_deptos)
    end

    @objective(m, Max, supUtil)
    optimize!(m)


    termination_status(m)
    superficieUtil     = value(supUtil)
    superficieComun    = value(supComun)
    superficieTerraza  = value(supTerraza)
    superficieInterior = value(supInterior) 
    descuento_dfl2_     = value(descuento_dfl2)

    # gather results
    if termination_status(m) == MOI.OPTIMAL
        superficieUtil     = value(supUtil)
        superficieComun    = value(supComun)
        superficieTerraza  = value(supTerraza)
        superficieInterior = value(supInterior)
        superficieComunPrimerPiso = value(supComunPrimerPiso)
        superficieTerrazaPrimerPiso = value(supTerrazaPrimerPiso)   
        superficieInteriorPrimerPiso = value(supInteriorPrimerPiso)
        superficieComunPisosSup   = value(supComunPisosSup)
        superficieTerrazaPisosSup = value(supTerrazaPisosSup)
        superficieInteriorPisosSup = value(supInteriorPisosSup) 
        totalDeptos = sum(value.(numDeptos))
        deptosTipo = value.(numDeptos)[:]
    else
        deptosTipo = Int[]
    end

    display("SupEdifTotal = " * string(round(JuMP.value(supEdifTotal), digits=1)))
    display(
        "    " *
        "PrimerPiso | " *
        "PisosSup | " *
        "Total"
    )

    display(
        "SupComun = " *
        string(round(superficieComunPrimerPiso, digits=1)) * " | " *
        string(round(superficieComunPisosSup, digits=1)) * " | " *
        string(round(superficieComun, digits=1))
    )
    display(
        "SupTerraza = " *
        string(round(superficieTerrazaPrimerPiso, digits=1)) * " | " *
        string(round(superficieTerrazaPisosSup, digits=1)) * " | " *
        string(round(superficieTerraza, digits=1))
    )
    display(
        "SupInterior = " *
        string(round(superficieInteriorPrimerPiso, digits=1)) * " | " *
        string(round(superficieInteriorPisosSup, digits=1)) * " | " *
        string(round(superficieInterior, digits=1))
    )
    display(
        "Total = " *
        string(round(superficieComunPrimerPiso+superficieTerrazaPrimerPiso+superficieInteriorPrimerPiso, digits=1)) * " | " *
        string(round(superficieComunPisosSup+superficieTerrazaPisosSup+superficieInteriorPisosSup, digits=1)) * " | " *
        string(round(superficieComun+superficieTerraza+superficieInterior, digits=1))
    )

    display("Total = " * string(round(superficieComun+superficieTerraza+superficieInterior, digits=1)))
    display("SupUtil = " * string(round(superficieUtil, digits=1)))
    print(JuMP.value.(numDeptosPrimerPiso))
    print("\n")
    print(JuMP.value.(numDeptosPorPisoSup) * (sum(vec_np_opt) - 1))
    print("\n")
    print(JuMP.value.(numDeptos))
    print("\n")
    print("\n")
    print("")

    dict_edificio_deptos = OrderedDict(
    "supUtil" => value(supUtil),
    "supUtilPrimerPiso" => value(supUtilPrimerPiso),
    "supUtilPisosSup" => value(supUtilPisosSup),
    "supComunPrimerPiso" => value(supComun),
    "supComunPrimerPiso" => value(supComunPrimerPiso),
    "supComunPisosSup" => value(supComunPisosSup),
    "supTerraza" => value(supTerraza),
    "supTerrazaPrimerPiso" => value(supTerrazaPrimerPiso),
    "supTerrazaPisosSup" => value(supTerrazaPisosSup),
    "supInterior" => value(supInterior),
    "supInteriorPrimerPiso" => value(supInteriorPrimerPiso),
    "supInteriorPisosSup" => value(supInteriorPisosSup),
    "numDeptosTipo" => value.(numDeptos)[:],
    "numDeptos" => value(totalDeptos)
    )

    return dict_edificio_deptos
end


