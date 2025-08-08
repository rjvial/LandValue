# LandValue - Claude Code Memory

## Project Overview
LandValue is a sophisticated Julia-based real estate development optimization system designed for the Chilean market. It performs comprehensive land value analysis, building volumetric optimization, and generates detailed 3D building models while ensuring compliance with Chilean urban development regulations. The system integrates with Neo4j for property graph data management and AWS for scalable cloud infrastructure.

## Key Domain Concepts
- **Predios**: Individual land parcels with associated geometric properties and regulatory constraints
- **Combis**: Strategic land combinations (aggregated parcels) optimized for development potential
- **Volumetric Optimization**: Advanced 3D building volume optimization considering shadows, setbacks, height limits, and regulatory constraints
- **Cabida**: Comprehensive development feasibility analysis covering architectural, commercial, and financial aspects
- **Normativa**: Chilean urban planning regulations, zoning restrictions, and building codes

## Architecture & Core Structure

### Main Module: `src/LandValue.jl` (lines 1-218)
- Defines fundamental geometric data structures: `PolyShape`, `LineShape`, `PointShape`
- Implements geometric operator overloading (addition, subtraction, multiplication) for shape objects
- Contains comprehensive development data structures: `DatosCabidaPredio`, `DatosCabidaArquitectura`, `DatosCabidaComercial`, `DatosCabidaUnit`, `DatosCabidaRentabilidad`
- Orchestrates module inclusion and exports core functionality
- Includes both `polyShape.jl` and `polyPlot.jl` modules

### CRITICAL PRIORITY MODULE: `polyShape` (`src/polyShape.jl`)
**🔴 MANDATORY: Always use polyShape module functions for ALL geometric operations in new code 🔴**

#### Core Geometric Operations:
- **Shape Analysis**: `extraeInfoPoly`, `largoLadosPoly`, `isPolyConvex`, `isPolyInPoly`, `polyArea`
- **Shape Manipulation**: `polyDifference`, `polyUnion`, `shapeBuffer`, `polyIntersect`, `polyOffset`
- **Geometric Conversions**: `shape2geom`, `geom2shape`, `astext2polyshape`, `astext2lineshape`
- **Shape Processing**: `shapeContains`, `shapeArea`, `shapeDifference`, `shapeIntersect`, `shapeUnion`, `shapeHull`
- **Shape Utilities**: `shapeSimplify`, `shapeSimplifyTopology`, `subShape`, `shapeVertex`, `numVertices`, `shapeCentroid`
- **Distance & Proximity**: `shapeDistance`, `partialDistance`, `minPolyDistance`, `pointLineDist`, `lineLineDist`
- **Geometric Transformations**: `polyBox`, `polyRotate`, `polyReverse`, `setPolyOrientation`, `polyReproject`
- **Advanced Operations**: `polyShrink`, `polyProyeccion`, `poly2Constraints`, `constraints2poly`, `convHull`
- **Clipper Integration**: `shape2clipper`, `clipper2shape`, `clipper_union`, `clipper_difference`, `clipper_intersection`, `clipper_offset`

### Visualization Module: `polyPlot` (`src/polyPlot.jl`)
**🔴 Use polyPlot for ALL visualization of geometric objects 🔴**

#### Plotting Functions:
- **2D Visualization**: `plotPolyshape2D` for PolyShape, LineShape, and PointShape objects
- **3D Visualization**: `plotPolyshape2Din3D`, `plotPolyshape3D` for 3D geometric rendering
- **Multi-object Plotting**: `plotPolyshape2DVecin3D` for arrays of shapes at different heights
- **Matplotlib Integration**: Direct PyPlot integration with PathPatch for complex geometric rendering
- **Image Processing**: `imageWhiteSpaceReduction` for plot optimization

## Key Dependencies & Technologies
- **Optimization Engines**: JuMP, Cbc, Ipopt, BlackBoxOptim, NOMAD, SCIP, SCS
- **Geometric Processing**: ArchGDAL, Clipper, LazySets, WellKnownGeometry, Proj  
- **Database Integration**: LibPQ (PostgreSQL), custom Neo4j SSH integration (`neo4j_julia.jl`)
- **Cloud Infrastructure**: AWS SDK, AWSS3 for EC2 and S3 management
- **Visualization**: PyPlot, PyCall for 2D/3D plotting, Plots for additional chart types
- **Data Management**: DataFrames, CSV, JSON3, XLSX, Tables
- **Image Processing**: ImageBinarization for plot enhancement
- **Mathematical**: StaticArrays, LinearAlgebra, Distributions, Combinatorics

## Script Categories & Workflow

### Strategic Property Analysis Scripts
- `script_0_prediosEstrategicos.jl`: Identifies strategic development properties using Neo4j graph queries with sophisticated geometric filters (rectangularity ≥0.92, convexity, size constraints 800-4000m²)
- `script_0_segmentoCalles.jl`: Performs comprehensive street segment analysis for urban planning

### Volumetric Optimization Scripts  
- `script_2A_optim_volumetrica_indiv.jl`: Individual property volumetric optimization with shadow analysis
- `script_2A_optim_volumetrica_paralela.jl`: High-performance parallel volumetric optimization for multiple properties

### Visualization & Output Scripts
- `script_4_generaImagenesCabida.jl`: Automated generation of development capacity visualization images
- `script_6_generaCodigoScr.jl`: SCR (Sistema de Coordenadas de Referencia) code generation
- `script_8_generaGeojson.jl`: GeoJSON export functionality for GIS integration

## Core Modules by Functional Category

### Optimization & Analysis Modules
- `opti_edificio.jl`: Core building optimization algorithms with constraint handling
- `opti_edificio_deptos.jl`: Apartment building optimization with unit mix analysis
- `opti_edificio_vol.jl`: Volumetric building optimization considering setbacks and shadows
- `opti_vol_estacionamiento.jl`: Parking space volume optimization
- `optimal_pricing.jl`: Economic optimization and pricing strategies
- `optimal_lot_selection.jl`: Strategic lot selection algorithms
- `quad_opti_vol.jl`, `quad_opti_sol_ini.jl`: Quadratic optimization utilities and initial solutions

### Geometric Processing & Shadow Analysis
- `generaSombraEdificio.jl`: Building shadow generation with solar geometry calculations
- `generaSombraTeor.jl`: Theoretical shadow calculations for volumetric planning
- `generaVol3D.jl`: 3D volume generation and manipulation
- `generaPoligonoCorte.jl`: Advanced polygon cutting and intersection operations
- `plotBaseEdificio3D.jl`: 3D building base visualization and rendering

### Data Integration & Database Modules
- `pg_julia.jl`: PostgreSQL database connection, queries, and data management
- `neo4j_julia.jl`: Neo4j graph database operations using SSH tunneling and cypher-shell
- `aws_julia.jl`: AWS EC2 instance management, S3 operations, and cloud infrastructure
- `obtiene_requerimientos_normativos.jl`: Chilean regulatory requirements retrieval and parsing
- `obtiene_geometrias_codigo_predial.jl`: Property geometry retrieval by cadastral code

### Utility & Processing Modules
- `resultConverter.jl`: Multi-format result conversion and export utilities
- `expression_converter.jl`: Mathematical expression parsing and conversion
- `create_scr.jl`: SCR file generation for coordinate reference systems
- `create_edificio_geojson.jl`: Building-specific GeoJSON generation
- `obtieneCalles.jl`: Street and road network data processing
- `graphMod.jl`: Graph analysis using Graphs.jl and MetaGraphs for network operations

## Development Patterns & Conventions

### Code Architecture Philosophy
- **Self-documenting code**: No inline comments policy - function names and structure convey intent
- **Mutable struct patterns**: Extensive use of mutable structs for geometric and data containers
- **Functional module organization**: One logical function group per module with clear separation
- **Explicit type annotations**: Strong typing for function parameters and return values

### MANDATORY Geometric Operations Protocol
**🔴 CRITICAL: All new geometric code MUST use polyShape module functions 🔴**

1. **Shape Creation**: Use `geom2shape()` for converting from GDAL geometries
2. **Shape Operations**: Use polyShape functions (`polyUnion`, `polyDifference`, `polyIntersect`) instead of raw geometric libraries
3. **Visualization**: Use polyPlot functions (`plotPolyshape2D`, `plotPolyshape3D`) for all shape rendering
4. **Conversions**: Use `shape2geom()` for converting to GDAL for external system integration

### Database Connectivity Patterns
- **Neo4j**: Remote SSH connection to EC2 instance using cypher-shell with key pair authentication
- **PostgreSQL**: Direct connection using LibPQ with credential-based authentication
- **AWS**: EC2 instance lifecycle management with S3 integration for data storage

### Environment & Configuration Management
- `secrets.env`: Centralized storage for AWS credentials, database passwords, and API keys
- **DotEnv pattern**: Environment variables loaded via DotEnv package throughout the system
- **SSH authentication**: Neo4j access via SSH key pair (`neo4j-key-pair.pem`) authentication

## Testing & Development Workflow
- **Custom validation**: No standard test framework - verify testing patterns in project root
- **Docker containerization**: Full Docker support for consistent deployment environments
- **AWS infrastructure**: EC2 templates and automated deployment configurations

## Current Development Context & Status
- **Active branch**: `dev_docker` (Docker-based development workflow)
- **Recent improvements**: Code organization, optimization algorithm refinements
- **Modified files**: Volumetric optimization scripts with enhanced performance
- **New functionality**: Strategic property analysis scripts with improved geometric filtering
- **Module integration**: polyPlot module recently integrated with polyShape for comprehensive geometric visualization

## File Naming & Organization Conventions
- `script_N_`: Sequential executable analysis scripts (numbered workflow steps)
- `opti_`: Optimization algorithm modules with specific focus areas
- `genera_`: Generation and creation utilities for various output formats
- `obtiene_`: Data retrieval and processing functions
- **Descriptive naming**: Compound names with underscores for clarity and searchability

## Integration & Deployment Architecture
- **Containerization**: Complete Dockerfile for consistent deployment across environments
- **AWS templates**: Comprehensive JSON templates for EC2 infrastructure setup and management
- **Data interchange**: CSV for tabular results, GeoJSON for spatial data exchange
- **Coordinate systems**: Proj.jl integration for coordinate transformations between Chilean and international systems

## PRIORITY DEVELOPMENT GUIDELINES

### 🔴 MANDATORY REQUIREMENTS FOR ALL NEW CODE:

1. **GEOMETRIC OPERATIONS**: Use polyShape module functions exclusively
   - ✅ `polyUnion(shape1, shape2)` instead of direct geometric library calls
   - ✅ `plotPolyshape2D(shape)` for visualization
   - ✅ `shapeBuffer(shape, distance)` for buffering operations

2. **CODE STRUCTURE**: Follow established patterns
   - Mutable struct definitions for data containers
   - Operator overloading for geometric operations
   - Descriptive function names without inline comments

3. **DATABASE INTEGRATION**: Use existing connection patterns
   - Neo4j via SSH tunnel for property graphs
   - PostgreSQL via LibPQ for relational data
   - AWS SDK for cloud infrastructure

4. **VISUALIZATION**: Use polyPlot for all geometric rendering
   - 2D: `plotPolyshape2D()`
   - 3D: `plotPolyshape3D()` or `plotPolyshape2Din3D()`
   - Multiple objects: `plotPolyshape2DVecin3D()`

5. **ENVIRONMENT**: Maintain configuration standards
   - Use DotEnv for secrets management
   - Follow SSH key authentication patterns
   - Maintain Docker compatibility

### ⚠️ AVOID:
- Direct calls to ArchGDAL, Clipper, or other geometric libraries (use polyShape wrappers)
- Creating new geometric data structures (use existing PolyShape, LineShape, PointShape)
- Inline comments (code should be self-documenting)
- Breaking Docker containerization compatibility