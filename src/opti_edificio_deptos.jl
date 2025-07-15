function opti_edificio_deptos(
        dcn, dca, dcp, dcc,
        vec_ps_opt, vec_np_opt,
        superficieTerreno::Real, superficieTerrenoBruto::Real, flag_dfl2
    )

    # Base areas
    K = length(vec_ps_opt) # num stacks
    vec_areaBasal = [polyShape.polyArea(ps) for ps in vec_ps_opt]

    # Density and max deptos
    superficieDensidad = dcn.flagDensidadBruta ? superficieTerrenoBruto : superficieTerreno
    maxDeptos = floor(dcn.densidadMax / 4 * superficieDensidad / 10000)
    num_pisos = sum(vec_np_opt)
    num_pisos_regulares = num_pisos - 1         # Pisos regulares (sin primer piso)

    # Occupation and constructibility
    maxOcupacion = dcn.coefOcupacion * superficieTerreno
    maxConstruct = superficieTerreno * dcn.coefConstructibilidad * (1 + 0.3 * dcp.fusionTerrenos)

    # Variants and area matrices
    numTipos = length(dcc.supDeptoUtil)
    vecSupUtil    = dcc.supDeptoUtil 
    vecSupTerraza = vecSupUtil .* 0.1
    vecSupInterior= vecSupUtil .- 0.5 * vecSupTerraza

    # Total built footprint (for common areas minimums)
    supEdifTotal = sum(vec_areaBasal[i] *vec_np_opt[i] for i in 1:K)

    # Build JuMP model
    m = Model(Cbc.Optimizer)
    set_optimizer_attribute(m, "ratioGap", 0.001)
    set_optimizer_attribute(m, "logLevel", 0)

    @variables(m, begin
        # choose at most one variant per type
        z[u=1:numTipos], Bin
        # group counts (2 dpts per group)
        y_primerPiso[u=1:numTipos] >= 0, Int
        y_PisosSup[u=1:numTipos] >= 0, Int
        # deptos per type+variant
        numDeptosPrimerPiso[u=1:numTipos] >= 0, Int
        numDeptosPorPisoSup[u=1:numTipos] >= 0, Int
        # common areas
        supComunPrimerPiso >= 0
        supComunPisosSup   >= 0
        descuento_dfl2     >= 0
    end)

    # expressions
    @expression(m, supUtilPrimerPiso,    sum(vecSupUtil[u]    * numDeptosPrimerPiso[u] for u=1:numTipos))
    @expression(m, supUtilPisosSup,      sum(vecSupUtil[u]    * numDeptosPorPisoSup[u] * num_pisos_regulares for u=1:numTipos))
    @expression(m, supTerrazaPrimerPiso, sum(vecSupTerraza[u] * numDeptosPrimerPiso[u] for u=1:numTipos))
    @expression(m, supTerrazaPisosSup,   sum(vecSupTerraza[u] * numDeptosPorPisoSup[u] * num_pisos_regulares for u=1:numTipos))
    @expression(m, supInteriorPrimerPiso,sum(vecSupInterior[u]* numDeptosPrimerPiso[u] for u=1:numTipos))
    @expression(m, supInteriorPisosSup,  sum(vecSupInterior[u]* numDeptosPorPisoSup[u] * num_pisos_regulares for u=1:numTipos))

    @expression(m, supUtil,     supUtilPrimerPiso    + supUtilPisosSup)
    @expression(m, supComun,    supComunPrimerPiso   + supComunPisosSup)
    @expression(m, supTerraza,  supTerrazaPrimerPiso + supTerrazaPisosSup)
    @expression(m, supInterior, supInteriorPrimerPiso+ supInteriorPisosSup)
    
    @expression(m, supEdif,     supComun + supTerraza + supInterior)
    @expression(m, numDeptos,   numDeptosPrimerPiso + numDeptosPorPisoSup * num_pisos_regulares)

    # constraints
    @constraints(m, begin
        
        # at least one chosen
        sum(z) >= 1

        # numDeptos > 0 solo si se elije la variante y tipo correspondiente
        [u=1:numTipos], numDeptos[u] <= maxDeptos * z[u]

        # Tipo deptos y variante deben estar en numeros pares
        [u=1:numTipos], numDeptosPrimerPiso[u] == 2 * y_primerPiso[u]
        [u=1:numTipos], numDeptosPorPisoSup[u] == 2 * y_PisosSup[u]
        
        # group limits
        [u=1:numTipos], y_PisosSup[u] <= maxDeptos * z[u]
        [u=1:numTipos], y_primerPiso[u] <= y_PisosSup[u]
                
        # Max densidad 
        sum(numDeptos) <= maxDeptos
        
        # restricciones de area comun
        descuento_dfl2 <= flag_dfl2 * 0.2 * supUtil 
        descuento_dfl2 <= flag_dfl2 * supComun
        supComunPrimerPiso >= 0.30 * supUtil / num_pisos #minSupComunPrimerPiso
        supComunPisosSup   >= 0.15 * supUtil  #minSupComunPisosSup

        # balance de superficie por piso 
        supComunPrimerPiso + supTerrazaPrimerPiso + supInteriorPrimerPiso == vec_areaBasal[1]
        supComunPisosSup   + supTerrazaPisosSup   + supInteriorPisosSup == sum(vec_areaBasal[i] * (i==1 ? vec_np_opt[1]-1 : vec_np_opt[i]) for i=1:K)
        
        # Max constructibilidad
        supUtil + supComun - descuento_dfl2 <= maxConstruct

    end)

    @objective(m, Max, supUtil)
    optimize!(m)

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

        # parking
        totalDeptos = sum(value.(numDeptos))
        est_viv     = dcc.estacionamientosPorViv * totalDeptos
        est_vis     = est_viv * dcn.porcAdicEstacVisitas
        est_disc    = totalDeptos <= 20 ? 1 : totalDeptos <= 50 ? 2 : totalDeptos <= 200 ? 3 : totalDeptos <= 400 ? 4 : totalDeptos <= 500 ? 5 : 0.01*totalDeptos
        bodegas     = totalDeptos * dcc.bodegasPorViv

        so = SalidaOptimizacion(
            value.(numDeptos)[:],
            totalDeptos,
            min(vec_areaBasal[1], maxOcupacion),
            superficieUtil,
            sum(vec_np_opt), sum(vec_np_opt)*dca.alturaPiso,
            value(supInterior), value(supTerraza), value(supComun),
            value(supEdif), vec_areaBasal[1], est_viv, est_vis, est_disc, 0, bodegas
        )
        sh = SalidaHolgura(
            maxOcupacion - vec_areaBasal[1],
            maxConstruct - superficieUtil,
            maxDeptos - totalDeptos
        )
        deptosTipo = value.(numDeptos)[:]
    else
        so, sh, deptosTipo = nothing, nothing, Int[]
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
        string(round(superficieComunPisosSup,  digits=1)) * " | " *
        string(round(superficieComun,          digits=1))
    )
    display(
        "SupTerraza = " *
        string(round(superficieTerrazaPrimerPiso, digits=1)) * " | " *
        string(round(superficieTerrazaPisosSup,    digits=1)) * " | " *
        string(round(superficieTerraza,            digits=1))
    )
    display(
        "SupInterior = " *
        string(round(superficieInteriorPrimerPiso, digits=1)) * " | " *
        string(round(superficieInteriorPisosSup,    digits=1)) * " | " *
        string(round(superficieInterior,            digits=1))
    )
    display(
        "Total = " *
        string(round(superficieComunPrimerPiso+superficieTerrazaPrimerPiso+superficieInteriorPrimerPiso, digits=1)) * " | " *
        string(round(superficieComunPisosSup+superficieTerrazaPisosSup+superficieInteriorPisosSup,    digits=1)) * " | " *
        string(round(superficieComun+superficieTerraza+superficieInterior,            digits=1))
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

    return so, sh, deptosTipo
end


