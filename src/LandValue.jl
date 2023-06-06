module LandValue

    using JuMP, NOMAD, Cbc, BlackBoxOptim, ArchGDAL, DotEnv #,
            # NonconvexBayesian, NonconvexIpopt, NonconvexNLopt, Distributions
    

    mutable struct PolyShape
        Vertices::Array{Array{Float64,2},1}
        NumRegions::Int64
    end

    mutable struct LineShape 
        Vertices::Array{Array{Float64,2},1}
        NumLines::Int64
    end

    mutable struct PointShape
        Vertices::Array{Float64,2}
        NumPoints::Int64
    end

    function Base.:+(p1::PointShape, p2::PointShape)::PointShape
        V1 = deepcopy(p1.Vertices)
        numPoints_1 = p1.NumPoints
        V2 = deepcopy(p2.Vertices)
        V = deepcopy(V1)
        for i = 1:numPoints_1
            V[i,:] = V1[i,:] + V2[1,:]
        end
        p = PointShape(V, numPoints_1)
        return p
    end
    function Base.:+(l1::LineShape, p2::PointShape)::LineShape
        V1 = deepcopy(l1.Vertices)
        numLines_1 = l1.NumLines
        V2 = deepcopy(p2.Vertices)
        V = deepcopy(V1)
        for i = 1:numLines_1
            V[i][1,:] = V[i][1,:] + V2[1,:]
            V[i][2,:] = V[i][2,:] + V2[1,:]
        end
        l = LineShape(V, numLines_1)
        return l
    end
    function Base.:-(l1::LineShape, p2::PointShape)::LineShape
        V1 = deepcopy(l1.Vertices)
        numLines_1 = l1.NumLines
        V2 = deepcopy(p2.Vertices)
        V = deepcopy(V1)
        for i = 1:numLines_1
            V[i][1,:] = V[i][1,:] - V2[1,:]
            V[i][2,:] = V[i][2,:] - V2[1,:]
        end
        l = LineShape(V, numLines_1)
        return l
    end
    function Base.:-(p1::PointShape, p2::PointShape)::PointShape
        V1 = deepcopy(p1.Vertices)
        numPoints_1 = p1.NumPoints
        V2 = deepcopy(p2.Vertices)
        V = deepcopy(V1)
        for i = 1:numPoints_1
            V[i,:] = V[i,:] - V2[1,:]
        end
        p = PointShape(V, numPoints_1)
        return p
    end

    function Base.:*(l::LineShape, f::Union{Int64,Float64})::LineShape
        numLines = l.NumLines
        V = deepcopy(l.Vertices)
        for i = 1:numLines
            dvec = [V[i][2,:] - V[i][1,:]] * f
            V[i][2,:] = V[i][1,:] + dvec[1]
        end
        l = LineShape(V, numLines)
        return l
    end
    function Base.:*(p::PointShape, f::Union{Int64,Float64})::PointShape
        numPoints = p.NumPoints
        V = deepcopy(p.Vertices)
        for i = 1:numPoints
            V[i,:] = V[i,:] * f
        end
        p = PointShape(V, numPoints)
        return p
    end


    GeomObject = Union{PolyShape,LineShape,PointShape}

    PosDimGeom = Union{PolyShape,LineShape}


    mutable struct DatosCabidaPredio
        x::Array{Float64,1}
        y::Array{Float64,1}
        ladosConCalle::Array{Int64,1}
        anchoEspacioPublico::Array{Float64,1}
        fusionTerrenos::Int64
        distanciaMetro::Int64
    end

    mutable struct DatosCabidaNormativa
        distanciamiento::Float64
        antejardin::Float64
        rasante::Float64
        rasanteSombra::Float64
        alturaMax::Float64
        maxPisos::Float64
        coefOcupacion::Float64
        supPredialMin::Float64
        densidadMax::Float64
        flagDensidadBruta::Bool
        coefConstructibilidad::Float64
        estacionamientosPorViv::Float64
        porcAdicEstacVisitas::Float64
        supPorEstacionamiento::Float64
        supPorBodega::Float64
        estBicicletaPorEst::Float64
        bicicletasPorEst::Float64
        flagCambioEstPorBicicleta::Bool
        maxSubte::Int64
        coefOcupacionEst::Float64
        sepEstMin::Float64
        reduccionEstPorDistMetro::Bool
        DatosCabidaNormativa() = new()
    end

    mutable struct DatosCabidaArquitectura
        alturaPiso::Float64
        porcSupComun::Float64
        porcTerraza::Float64
        anchoMin::Float64
        anchoMax::Float64
        DatosCabidaArquitectura() = new()
    end

    mutable struct DatosCabidaComercial
        tipoUnidad::Array{String,1}
        supDeptoUtil::Array{Float64,1}
        supInterior::Array{Float64,1}
        supTerraza::Array{Float64,1}
        # numeroDormitorios::Array{Float64,1}
        # numeroBanos::Array{Float64,1}
        estacionamientosPorViv::Array{Float64,1}
        bodegasPorViv::Array{Float64,1}
        Precio_Estimado::Array{Float64,1}
        # precioVenta::Array{Float64,1}
        # maxPorcTipoDepto::Array{Float64,1}
        DatosCabidaComercial() = new()
    end

    mutable struct DatosCabidaUnit
        duracionProyecto::Float64
        costoTerreno::Float64
        comisionCorredor::Float64
        demolicion::Float64
        otrosTerreno::Float64
        losaSNT::Float64
        losaBNT::Float64
        ito::Float64 # por mes
        ivaConstruccion::Float64
        creditoIvaConstruccion::Float64
        arquitectura::Float64
        calculo::Float64
        mecanicaSuelo::Float64
        topografia::Float64
        proyectosEspecialidades::Float64
        empalmes::Float64
        aportesUrbanos::Float64
        mitigacionesViales::Float64
        derechosPermisosMunicipales::Float64
        marketing::Float64
        habilitacionSalaVentaComunes::Float64
        gestionAdministracion
        contabilidad::Float64 # por mes
        legales::Float64
        seguros::Float64
        postVentaInmobiliaria::Float64
        seguroVentaEnVerde::Float64   
        variosVentas::Float64
        costoFinanciero::Float64
        imprevistos::Float64
        DatosCabidaUnit() = new()
    end


    # Rentabilidad exigida
    mutable struct DatosCabidaRentabilidad
        retornoExigido::Float64
    end

    struct SalidaNormativa
        maxNumDeptos::Float64
        maxOcupacion::Float64
        maxConstructibilidad::Float64
        maxPisos::Float64
        maxAltura::Float64
        minEstacionamientosVendibles::Float64
        minEstacionamientosVisita::Float64
        minEstacionamientosDiscapacitados::Float64
    end

    struct SalidaArquitectonica
        numDeptosTipo::Array{Float64,1}
        numDeptos::Float64
        ocupacion::Float64
        constructibilidad::Float64
        numPisos::Float64
        altura::Float64
        superficieInterior::Float64
        superficieTerraza::Float64
        superficieComun::Float64
        superficieEdificadaSNT::Float64
        superficiePorPiso::Float64
        estacionamientosVendibles::Float64
        estacionamientosVisita::Float64
        numEstacionamientos::Float64
        numBicicleteros::Float64
        numBodegas::Float64
    end

    struct SalidaTerreno
        superficieTerreno::Float64
        superficieBruta::Float64
        costoTerreno::Float64
        costoUnitTerreno::Float64
        costoCorredor::Float64
        costoDemolicion::Float64
        otrosTerreno::Float64
        costoTotalTerreno::Float64
        costoUnitTerrenoTotal::Float64
    end

    struct SalidaOptimizacion
        dualMaxOcupación::Float64
        dualMaxConstructibilidad::Float64
        dualMaxDensidad::Float64
    end


    struct SalidaIndicadores
        ingresosVentas::Float64
        costoTotal::Float64
        margenAntesImpuesto::Float64
        impuestoRenta::Float64
        utilidadDespuesImpuesto::Float64
        rentabilidadTotalBruta::Float64
        rentabilidadTotalNeta::Float64
        incidenciaTerreno::Float64
    end

    struct SalidaMonetaria
        ingresosVentaDeptos::Float64
        ingresosVentas::Float64
        costoTerrenoTotal::Float64
        costoUnitarioTerrenoTotal::Float64
        costoConstruccion::Float64
        balanceIva::Float64
        costoInmobiliario::Float64
        costosMarketingVentas::Float64
        costosAdministracion::Float64
        costosVariosVenta::Float64
        costosFinancieros::Float64
        imprevistos::Float64
        costoTotal::Float64
    end

    mutable struct ResultadoCabida
        salidaNormativa::SalidaNormativa
        salidaArquitectonica::SalidaArquitectonica
        salidaIndicadores::SalidaIndicadores
        salidaTerreno::SalidaTerreno
        salidaMonetaria::SalidaMonetaria
        salidaOptimizacion::SalidaOptimizacion
        xopt::Array{Float64,1}
    end


    export DatosCabidaPredio, DatosCabidaNormativa, DatosCabidaArquitectura, DatosCabidaComercial, DatosCabidaUnit,
            DatosCabidaRentabilidad, SalidaArquitectonica, SalidaIndicadores, SalidaMonetaria,
            SalidaTerreno, SalidaOptimizacion, SalidaNormativa, GeomObject, PosDimGeom, PolyShape, LineShape, PointShape, 
            ResultadoCabida


    include("funcionPrincipal.jl")
    include("fo_bbo.jl")
    include("fo_nomad.jl")
    include("calculaAnguloRotacion.jl")
    include("generaSombraEdificio.jl")
    include("optiEdificio.jl")
    include("displayResults.jl")
    include("poly2D.jl")
    include("polyShape.jl")
    include("graphMod.jl")
    include("optim_nomad.jl")
    include("optim_bbo.jl")
    include("resultConverter.jl")
    include("generaVol3D.jl")
    include("generaSombraTeor.jl")
    include("pg_julia.jl")
    include("queryCabida.jl")
    include("obtieneCalles.jl")
    include("generaPoligonoCorte.jl")
    include("generaCotas.jl")
    include("create_scr.jl")
    include("create_edificio_geojson.jl")

    export funcionPrincipal, fo_bbo, fo_nomad, calculaAnguloRotacion, generaSombraEdificio, optiEdificio, displayResults, 
        optim_nomad, optim_bbo, poly2D, polyShape, graphMod, resultConverter, generaVol3D, generaSombraTeor, 
        pg_julia, obtieneCalles, generaPoligonoCorte, queryCabida, generaCotas, create_scr, create_edificio_geojson


end
