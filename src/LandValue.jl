module LandValue

    using JuMP, NOMAD, Cbc, BlackBoxOptim, ArchGDAL,
            NonconvexBayesian, NonconvexIpopt, NonconvexNLopt, Distributions
    

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

    GeomObject = Union{PolyShape,LineShape,PointShape}

    PosDimGeom = Union{PolyShape,LineShape}

    mutable struct FlagPlotEdif3D
        predio::Bool
        volTeorico::Bool
        volConSombra::Bool
        edif::Bool
        sombraVolTeorico_p::Bool
        sombraVolTeorico_o::Bool
        sombraVolTeorico_s::Bool
        sombraEdif_p::Bool
        sombraEdif_o::Bool
        sombraEdif_s::Bool
        FlagPlotEdif3D() = new()
    end


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
        dualMaxOcupaci??n::Float64
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
            FlagPlotEdif3D, ResultadoCabida


    include("funcionPrincipal.jl")
    include("fo_bbo.jl")
    include("fo_nomad.jl")
    include("calculaAnguloRotacion.jl")
    include("generaSombraEdificio.jl")
    include("optiEdificio.jl")
    include("displayResults.jl")
    include("plotBaseEdificio3D.jl")
    include("poly2D.jl")
    include("polyShape.jl")
    include("graphMod.jl")
    include("optim_nomad.jl")
    include("optim_bbo.jl")
    include("resultConverter.jl")
    include("generaVol3D.jl")
    include("generaSombraTeor.jl")
    include("generaSupBruta.jl")
    include("pg_julia.jl")
    include("queryCabida.jl")
    include("obtieneCalles.jl")
    include("generaPoligonoCorte.jl")
    include("generaCotas.jl")
    include("create_scr.jl")
    include("create_edificio_geojson.jl")
    include("bid_prices.jl")
    include("bid_prices_pivot.jl")
    include("bid_price_aprendizaje_uniforme.jl")
    include("bid_price_dinamico_weibull.jl")
    include("bid_price_dinamico.jl")
    include("ajustaPrecioReserva.jl")

    export funcionPrincipal, fo_bbo, fo_nomad, calculaAnguloRotacion, generaSombraEdificio, optiEdificio, displayResults, 
        optim_nomad, optim_bbo, poly2D, polyShape, graphMod, resultConverter, plotBaseEdificio3D, generaVol3D, generaSombraTeor, 
        generaSupBruta, pg_julia, obtieneCalles, generaPoligonoCorte, queryCabida, generaCotas, create_scr, create_edificio_geojson, 
        bid_prices, bid_prices_pivot, bid_price_aprendizaje_uniforme, bid_price_dinamico, bid_price_dinamico_weibull, ajustaPrecioReserva


end
