function opti_deptos(
        dcn, dca, dcp, dcc,
        vec_ps_opt, vec_np_opt,
        superficieTerreno::Real, superficieTerrenoBruto::Real,
        sup_areaEdif::Real
    )
    # Base areas
    K = length(vec_ps_opt) # num stacks
    areaBasal = [polyShape.polyArea(ps) for ps in vec_ps_opt]

    # Density and max deptos
    superficieDensidad = dcn.flagDensidadBruta ? superficieTerrenoBruto : superficieTerreno
    maxDeptos_raw = floor(2 * dcn.densidadMax / 4 * superficieDensidad / 10000)
    num_pisos = sum(vec_np_opt)
    num_pisos_con_deptos = num_pisos - 1         # first floor empty
    maxDeptos = floor(Int, (maxDeptos_raw - 1) / num_pisos_con_deptos) * num_pisos_con_deptos

    # Occupation and constructibility
    maxOcupacion = dcn.coefOcupacion > 0 ? dcn.coefOcupacion * superficieTerreno : sup_areaEdif
    maxConstruct = dcn.coefConstructibilidad > 0 ?
        superficieTerreno * dcn.coefConstructibilidad * (1 + 0.3 * dcp.fusionTerrenos) :
        dcn.maxPisos[1] * sup_areaEdif

    # Variants and area matrices
    variantes = [.87, .9, 1.0, 1.1, 1.15]
    numVariantes = length(variantes)
    numTipos = length(dcc.supDeptoUtil)
    matSupUtil    = dcc.supDeptoUtil * variantes'
    matSupTerraza = matSupUtil .* 0.1
    matSupInterior= matSupUtil .- 0.5 * matSupTerraza

    # Total built footprint (for common areas minimums)
    supEdifTotal = sum(areaBasal[i] *vec_np_opt[i] for i in 1:K)

    # Build JuMP model
    m = Model(Cbc.Optimizer)
    set_optimizer_attribute(m, "ratioGap", 0.001)
    set_optimizer_attribute(m, "logLevel", 0)

    @variables(m, begin
        # choose at most one variant per type
        z[u=1:numTipos, v=1:numVariantes], Bin
        # group counts (2 dpts per group)
        y_primerPiso[u=1:numTipos, v=1:numVariantes] >= 0, Int
        y_PisosSup[u=1:numTipos, v=1:numVariantes] >= 0, Int
        # deptos per type+variant
        numDeptos[u=1:numTipos, v=1:numVariantes] >= 0, Int
        numDeptosPrimerPiso[u=1:numTipos, v=1:numVariantes] >= 0, Int
        numDeptosPorPisoSup[u=1:numTipos, v=1:numVariantes] >= 0, Int
        # common areas
        supComunPrimerPiso >= 0
        supComunPisosSup   >= 0
    end)

    # expressions
    @expression(m, supUtilPrimerPiso,    sum(matSupUtil[u,v]    * numDeptosPrimerPiso[u,v] for u=1:numTipos, v=1:numVariantes))
    @expression(m, supUtilPisosSup,      sum(matSupUtil[u,v]    * numDeptosPorPisoSup[u,v] * num_pisos_con_deptos for u=1:numTipos, v=1:numVariantes))
    @expression(m, supTerrazaPrimerPiso, sum(matSupTerraza[u,v] * numDeptosPrimerPiso[u,v] for u=1:numTipos, v=1:numVariantes))
    @expression(m, supTerrazaPisosSup,   sum(matSupTerraza[u,v] * numDeptosPorPisoSup[u,v] * num_pisos_con_deptos for u=1:numTipos, v=1:numVariantes))
    @expression(m, supInteriorPrimerPiso,sum(matSupInterior[u,v]* numDeptosPrimerPiso[u,v] for u=1:numTipos, v=1:numVariantes))
    @expression(m, supInteriorPisosSup,  sum(matSupInterior[u,v]* numDeptosPorPisoSup[u,v] * num_pisos_con_deptos for u=1:numTipos, v=1:numVariantes))

    @expression(m, supUtil,     supUtilPrimerPiso    + supUtilPisosSup)
    @expression(m, supComun,    supComunPrimerPiso   + supComunPisosSup)
    @expression(m, supTerraza,  supTerrazaPrimerPiso + supTerrazaPisosSup)
    @expression(m, supInterior, supInteriorPrimerPiso+ supInteriorPisosSup)
    @expression(m, supEdif,     supComun + supTerraza + supInterior)

    # constraints
    @constraints(m, begin
        # at most one variant per type
        [u=1:numTipos], sum(z[u,v] for v=1:numVariantes) <= 1
        # at least one chosen
        sum(z) >= 1
        # numDeptos > 0 solo si se elije la variante y tipo correspondiente
        [u=1:numTipos,v=1:numVariantes], numDeptos[u,v] <= maxDeptos * z[u,v]
        # groups to deptos mapping
        [u=1:numTipos,v=1:numVariantes], numDeptosPrimerPiso[u,v] == 2 * y_primerPiso[u,v]
        [u=1:numTipos,v=1:numVariantes], numDeptosPorPisoSup[u,v] == 2 * y_PisosSup[u,v]
        # group limits
        [u=1:numTipos,v=1:numVariantes], y_PisosSup[u,v] <= maxDeptos * z[u,v]
        [u=1:numTipos,v=1:numVariantes], y_primerPiso[u,v] <= y_PisosSup[u,v]
        # Suma deptos totales
        [u=1:numTipos,v=1:numVariantes], numDeptos[u,v] == numDeptosPrimerPiso[u,v] + numDeptosPorPisoSup[u,v] * num_pisos_con_deptos
        # Max densidad 
        sum(numDeptos) <= maxDeptos
        # common area minima
        supComunPrimerPiso >= 0.25 * supUtil / num_pisos #minSupComunPrimerPiso
        supComunPisosSup   >= 0.13 * supUtil / num_pisos #minSupComunPisosSup
        # area balance
        supComunPrimerPiso + supTerrazaPrimerPiso + supInteriorPrimerPiso == areaBasal[1]
        supComunPisosSup   + supTerrazaPisosSup   + supInteriorPisosSup == sum(areaBasal[i] * (i==1 ? vec_np_opt[1]-1 : vec_np_opt[i]) for i=1:K)
        # Max constructibilidad
        supUtil <= maxConstruct

        # supComun <= 0.2 * supUtil
    end)

    # @objective(m, Max, sum((1 / matSupUtil[u,v]) * numDeptos[u,v]  for u=1:numTipos, v=1:numVariantes))

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
            value.(sum(numDeptos, dims=2))[:],
            totalDeptos,
            min(areaBasal[1], maxOcupacion),
            superficieUtil,
            sum(vec_np_opt), sum(vec_np_opt)*dca.alturaPiso,
            value(supInterior), value(supTerraza), value(supComun),
            value(supEdif), areaBasal[1], est_viv, est_vis, est_disc, 0, bodegas
        )
        sh = SalidaHolgura(
            maxOcupacion - areaBasal[1],
            maxConstruct - superficieUtil,
            maxDeptos - totalDeptos
        )
        deptosTipo = value.(sum(numDeptos, dims=2))[:]
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


