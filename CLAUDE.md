# LandValue - Claude Code Memory

## Project Overview
LandValue is a sophisticated Julia-based real estate development optimization system designed specifically for the Chilean market. The system performs comprehensive land value analysis, advanced building volumetric optimization, and generates detailed 3D building models while ensuring strict compliance with Chilean urban development regulations. It integrates seamlessly with Neo4j for property graph data management and AWS for scalable cloud infrastructure deployment.

## Key Domain Concepts
- **Predios**: Individual land parcels with associated geometric properties, legal constraints, and regulatory requirements
- **Combis**: Strategic land combinations (aggregated parcels) optimized for maximum development potential
- **Volumetric Optimization**: Advanced 3D building volume optimization considering shadows, setbacks, height limits, floor area ratios, and regulatory constraints
- **Cabida**: Comprehensive development feasibility analysis covering architectural design, commercial viability, and detailed financial modeling
- **Normativa**: Chilean urban planning regulations, municipal zoning restrictions, building codes, and environmental compliance requirements

## Architecture & Core Structure

### Main Module: `src/LandValue.jl` (lines 1-219)
- Defines fundamental geometric data structures: `PolyShape`, `LineShape`, `PointShape`
- Implements sophisticated geometric operator overloading (addition, subtraction, multiplication) for shape objects
- Contains comprehensive development data structures: `DatosCabidaPredio`, `DatosCabidaArquitectura`, `DatosCabidaComercial`, `DatosCabidaUnit`, `DatosCabidaRentabilidad`
- Orchestrates modular system architecture with proper module inclusion and export management
- **Updated Module Structure**: Includes `polyShape.jl`, `polyPlot.jl`, `polyGdal.jl`, and `polyClipper.jl`

## 🔴 CRITICAL MODULE HIERARCHY & USAGE PATTERNS 🔴

### **TIER 1: Core Geometric Operations - polyShape Module (`src/polyShape.jl`)**
**🔴 MANDATORY: Use polyShape module for ALL core geometric operations in new code 🔴**

#### Essential Geometric Functions:
- **Shape Analysis**: `extraeInfoPoly`, `largoLadosPoly`, `isPolyConvex`, `isPolyInPoly`, `polyArea`
- **Shape Transformations**: `polyBox`, `polyRotate`, `polyReverse`, `setPolyOrientation`, `polyReproject`
- **Advanced Operations**: `polyShrink`, `polyProyeccion`, `poly2Constraints`, `constraints2poly`, `convHull`
- **Utility Functions**: `subShape`, `shapeVertex`, `numVertices`, `polyCopy`, `polyUnique`, `polyEliminateWithin`
- **Distance & Analysis**: `minPolyDistance`, `pointLineDist`, `lineLineDist`, `pointDistanceMat`
- **Line Operations**: `intersectLines`, `findPolyIntersection`, `parallelLineAtDist`, `lineAngle`, `extendLine`
- **Complex Processing**: `polyEliminaColineales`, `polyObtieneCruces`, `lineVec2polyShape`, `polyShape2lineVec`

### **TIER 2: GDAL Integration - polyGdal Module (`src/polyGdal.jl`)**
**🔴 USE polyGdal for ALL GDAL-based geometric operations 🔴**

#### GDAL-Specific Functions:
- **Geometric Conversions**: `geom2shape`, `shape2geom` - Convert between GDAL and custom shapes
- **WKT Processing**: `astext2polyshape`, `astext2lineshape` - Well-Known Text format conversion
- **GDAL Operations**: `shapeArea`, `shapeContains`, `shapeDifference`, `shapeIntersect`, `shapeUnion`
- **Advanced Processing**: `shapeHull`, `shapeSimplify`, `shapeSimplifyTopology`, `shapeBuffer`
- **Spatial Analysis**: `shapeCentroid`, `partialCentroid`, `shapeDistance`, `partialDistance`

### **TIER 3: Clipper Integration - polyClipper Module (`src/polyClipper.jl`)**
**🔴 USE polyClipper for ALL Clipper library operations 🔴**

#### Clipper-Specific Functions:
- **Shape Conversion**: `shape2clipper`, `clipper2shape` - Convert between shapes and Clipper paths
- **Boolean Operations**: `clipper_union`, `clipper_difference`, `clipper_intersection` - Precise polygon operations
- **Core Engine**: `clipper_op` - Base Clipper operation handler
- **Offsetting**: `clipper_offset`, `polyOffset` - Polygon expansion/contraction operations
- **Utilities**: `clipper_scale` - Coordinate scaling for precision

### **TIER 4: Visualization - polyPlot Module (`src/polyPlot.jl`)**
**🔴 USE polyPlot for ALL geometric visualization 🔴**

#### Comprehensive Plotting Functions:
- **2D Visualization**: `plotPolyshape2D` for PolyShape, LineShape, and PointShape objects
- **3D Visualization**: `plotPolyshape2Din3D`, `plotPolyshape3D` for advanced 3D geometric rendering
- **Multi-object Plotting**: `plotPolyshape2DVecin3D` for arrays of shapes at different heights and configurations
- **Advanced Features**: Direct PyPlot integration with PathPatch, image processing utilities, plot optimization

## Key Dependencies & Technologies
- **Optimization Engines**: JuMP, Cbc, Ipopt, BlackBoxOptim, NOMAD, SCIP, SCS - Multi-solver optimization framework
- **Geometric Processing**: ArchGDAL (GDAL integration), Clipper (Boolean operations), LazySets, WellKnownGeometry, Proj  
- **Database Integration**: LibPQ (PostgreSQL direct connection), custom Neo4j SSH integration via `neo4j_julia.jl`
- **Cloud Infrastructure**: AWS SDK, AWSS3 for EC2 lifecycle management and S3 operations
- **Visualization**: PyPlot, PyCall for 2D/3D matplotlib integration, Plots for additional charting
- **Data Management**: DataFrames, CSV, JSON3, XLSX, Tables for comprehensive data handling
- **Image Processing**: ImageBinarization for plot enhancement and optimization
- **Mathematical Libraries**: StaticArrays, LinearAlgebra, Distributions, Combinatorics for advanced computations

## Script Categories & Development Workflow

### Strategic Property Analysis Scripts
- `script_0_prediosEstrategicos.jl`: Advanced strategic property identification using Neo4j graph queries with sophisticated geometric filters (rectangularity ≥0.92, convexity analysis, size constraints 800-4000m²)
- `script_0_segmentoCalles.jl`: Comprehensive street segment analysis for urban planning and connectivity assessment

### Volumetric Optimization Scripts  
- `script_2A_optim_volumetrica_indiv.jl`: Individual property volumetric optimization with comprehensive shadow analysis and regulatory compliance
- `script_2A_optim_volumetrica_paralela.jl`: High-performance parallel volumetric optimization for multiple properties with distributed processing

### Visualization & Output Scripts
- `script_4_generaImagenesCabida.jl`: Automated generation of development capacity visualization images with 3D rendering
- `script_6_generaCodigoScr.jl`: SCR (Sistema de Coordenadas de Referencia) code generation for Chilean coordinate systems
- `script_8_generaGeojson.jl`: Comprehensive GeoJSON export functionality for GIS integration and web mapping

## Core Modules by Functional Category

### Advanced Optimization & Analysis Modules
- `opti_edificio.jl`: Core building optimization algorithms with advanced constraint handling and regulatory compliance
- `opti_edificio_deptos.jl`: Apartment building optimization with sophisticated unit mix analysis and market targeting
- `opti_edificio_vol.jl`: Volumetric building optimization considering complex setbacks, shadows, and height restrictions
- `opti_vol_estacionamiento.jl`: Parking space volume optimization with regulatory compliance and accessibility requirements
- `optimal_pricing.jl`: Advanced economic optimization and dynamic pricing strategies with market analysis
- `optimal_lot_selection.jl`: Strategic lot selection algorithms with multi-criteria decision analysis
- `quad_opti_vol.jl`, `quad_opti_sol_ini.jl`: Quadratic optimization utilities and sophisticated initial solution generation

### Geometric Processing & Shadow Analysis
- `generaSombraEdificio.jl`: Building shadow generation with precise solar geometry calculations and seasonal variations
- `generaSombraTeor.jl`: Theoretical shadow calculations for volumetric planning and regulatory compliance
- `generaVol3D.jl`: Advanced 3D volume generation, manipulation, and optimization
- `generaPoligonoCorte.jl`: Complex polygon cutting operations with intersection handling
- `plotBaseEdificio3D.jl`: Sophisticated 3D building base visualization and rendering systems

### Data Integration & Database Modules
- `pg_julia.jl`: PostgreSQL database connection, complex queries, spatial data management, and transaction handling
- `neo4j_julia.jl`: Neo4j graph database operations using SSH tunneling, cypher-shell integration, and distributed queries
- `aws_julia.jl`: Comprehensive AWS EC2 instance management, S3 operations, and cloud infrastructure automation
- `obtiene_requerimientos_normativos.jl`: Chilean regulatory requirements retrieval, parsing, and compliance validation
- `obtiene_geometrias_codigo_predial.jl`: Property geometry retrieval by cadastral code with spatial processing

### Utility & Processing Modules
- `resultConverter.jl`: Multi-format result conversion, export utilities, and data transformation
- `expression_converter.jl`: Mathematical expression parsing, conversion, and optimization
- `create_scr.jl`: SCR file generation for Chilean coordinate reference systems
- `create_edificio_geojson.jl`: Building-specific GeoJSON generation with metadata
- `obtieneCalles.jl`: Street and road network data processing with connectivity analysis
- `graphMod.jl`: Advanced graph analysis using Graphs.jl and MetaGraphs for network operations and pathfinding

## Development Patterns & Conventions

### Code Architecture Philosophy
- **Self-documenting code**: No inline comments policy - function names, structure, and type signatures convey complete intent
- **Mutable struct patterns**: Extensive use of mutable structs for geometric containers and data management
- **Modular architecture**: Clear functional separation with specialized modules for distinct operations
- **Explicit type annotations**: Strong typing system for function parameters, return values, and data structures

## 🔴 MANDATORY MODULE USAGE PROTOCOLS 🔴

### **GEOMETRIC OPERATIONS HIERARCHY** (CRITICAL - FOLLOW EXACTLY):

#### 1. **Core Geometric Operations** → Use `polyShape.function()`
```julia
# Shape creation and basic operations
ps = polyShape.polyBox(x, y, width, height, angle)
area = polyShape.polyArea(ps)
ps_rotated = polyShape.polyRotate(ps, angle, center)
```

#### 2. **GDAL-Based Operations** → Use `polyGdal.function()`  
```julia
# WKT conversion and GDAL operations
ps = polyGdal.astext2polyshape(wkt_string)
geom = polyGdal.shape2geom(ps)
buffered = polyGdal.shapeBuffer(ps, distance, segments)
hull = polyGdal.shapeHull(ps)
```

#### 3. **Clipper Library Operations** → Use `polyClipper.function()`
```julia
# Boolean operations and offsetting
union_result = polyClipper.polyUnion(ps1, ps2)  
offset_poly = polyClipper.polyOffset(ps, distance)
clipper_path = polyClipper.shape2clipper(ps)
```

#### 4. **Visualization Operations** → Use `polyPlot.function()`
```julia
# All plotting and visualization
fig, ax = polyPlot.plotPolyshape2D(ps, color="blue", alpha=0.7)
fig, ax = polyPlot.plotPolyshape3D(ps, height=10.0, color="red")
```

### **CRITICAL MODULE SEPARATION RULES**:
- ❌ **NEVER** use `polyShape.shapeBuffer()` → ✅ **USE** `polyGdal.shapeBuffer()`
- ❌ **NEVER** use `polyShape.polyOffset()` → ✅ **USE** `polyClipper.polyOffset()`
- ❌ **NEVER** use `polyShape.astext2polyshape()` → ✅ **USE** `polyGdal.astext2polyshape()`
- ❌ **NEVER** use direct geometric library calls → ✅ **USE** appropriate module wrappers

### Database Connectivity Patterns
- **Neo4j**: Remote SSH connection to EC2 instance using cypher-shell with RSA key pair authentication and encrypted tunneling
- **PostgreSQL**: Direct connection using LibPQ with connection pooling and transaction management
- **AWS**: Comprehensive EC2 instance lifecycle management with S3 integration for data storage and backup

### Environment & Configuration Management
- `secrets.env`: Centralized secure storage for AWS credentials, database passwords, API keys, and sensitive configuration
- **DotEnv pattern**: Environment variables loaded via DotEnv package with hierarchical configuration inheritance
- **SSH authentication**: Neo4j access via SSH key pair (`neo4j-key-pair.pem`) with secure authentication protocols

## Testing & Development Workflow
- **Custom validation**: No standard test framework - verify testing patterns and validation scripts in project root directory
- **Docker containerization**: Complete Docker support for consistent deployment environments across development, staging, and production
- **AWS infrastructure**: Comprehensive EC2 templates and automated deployment configurations for scalable cloud deployment

## Current Development Context & Status
- **Active branch**: `dev_docker` (Docker-based development workflow with containerized services)
- **Recent major improvements**: 
  - Module separation and organization with clear functional boundaries
  - Geometric operation optimization with specialized module architecture
  - Enhanced module reference correction for proper function routing
- **Module structure updates**: 
  - polyGdal functions properly separated for GDAL operations
  - polyClipper functions isolated for Clipper library operations
  - polyPlot functions dedicated to visualization tasks
- **Performance enhancements**: Strategic property analysis scripts with improved geometric filtering and processing optimization

## File Naming & Organization Conventions
- `script_N_`: Sequential executable analysis scripts with numbered workflow steps for systematic processing
- `opti_`: Optimization algorithm modules with specific focus areas and performance characteristics
- `genera_`: Generation and creation utilities for various output formats and data types
- `obtiene_`: Data retrieval and processing functions with database integration
- **Descriptive naming**: Compound names with underscores for maximum clarity, searchability, and maintainability

## Integration & Deployment Architecture
- **Containerization**: Complete Dockerfile with multi-stage builds for consistent deployment across diverse environments
- **AWS templates**: Comprehensive JSON templates for EC2 infrastructure setup, auto-scaling, and management automation
- **Data interchange**: CSV for tabular results export, GeoJSON for spatial data exchange, JSON for configuration management
- **Coordinate systems**: Proj.jl integration for coordinate transformations between Chilean national grid and international systems (UTM, WGS84)

## 🔴 PRIORITY DEVELOPMENT GUIDELINES 🔴

### **MANDATORY REQUIREMENTS FOR ALL NEW CODE:**

#### 1. **MODULE USAGE HIERARCHY** (CRITICAL - NO EXCEPTIONS):
```julia
# ✅ CORRECT module usage patterns:
ps_union = polyShape.polyUnion(ps1, ps2)           # Core operations
ps_buffered = polyGdal.shapeBuffer(ps, 10.0, 16)   # GDAL operations  
ps_offset = polyClipper.polyOffset(ps, -2.0)       # Clipper operations
fig, ax = polyPlot.plotPolyshape2D(ps)             # Visualization

# ❌ INCORRECT - DO NOT USE:
ps_buffered = polyShape.shapeBuffer(ps, 10.0)      # Wrong module
ps_offset = polyShape.polyOffset(ps, -2.0)         # Wrong module
```

#### 2. **GEOMETRIC PROCESSING PROTOCOL**:
- **Shape Creation**: Use `polyShape.polyBox()`, `polyShape.polyRotate()` for basic geometry
- **GDAL Integration**: Use `polyGdal.astext2polyshape()`, `polyGdal.shape2geom()` for format conversion
- **Boolean Operations**: Use `polyClipper.clipper_union()`, `polyClipper.clipper_difference()` for precision operations
- **Visualization**: Use `polyPlot.plotPolyshape2D()`, `polyPlot.plotPolyshape3D()` for all rendering

#### 3. **CODE STRUCTURE STANDARDS**:
- **Mutable struct definitions** for all data containers and geometric objects
- **Operator overloading** for intuitive geometric operations (`+`, `-`, `*`)
- **Descriptive function names** without inline comments (self-documenting code principle)
- **Explicit type annotations** for all function parameters and return values

#### 4. **DATABASE INTEGRATION STANDARDS**:
- **Neo4j**: Use `neo4j_julia.connection()` with SSH tunnel for property graphs and spatial queries
- **PostgreSQL**: Use `pg_julia` functions with LibPQ for relational data and complex spatial operations
- **AWS**: Use `aws_julia` functions for cloud infrastructure management and S3 operations

#### 5. **VISUALIZATION STANDARDS**:
- **2D Plotting**: `polyPlot.plotPolyshape2D()` for all 2D geometric visualization
- **3D Rendering**: `polyPlot.plotPolyshape3D()` or `polyPlot.plotPolyshape2Din3D()` for 3D visualizations
- **Multi-object scenes**: `polyPlot.plotPolyshape2DVecin3D()` for complex multi-height visualizations

#### 6. **ENVIRONMENT & CONFIGURATION**:
- **Use DotEnv** for all secrets and configuration management
- **Follow SSH key authentication** patterns for secure database connections
- **Maintain Docker compatibility** for consistent deployment environments

### **⚠️ CRITICAL PROHIBITIONS:**
- **Never use direct geometric library calls** (ArchGDAL, Clipper) - always use module wrappers
- **Never create new geometric data structures** - use existing PolyShape, LineShape, PointShape
- **Never add inline comments** - code must be self-documenting through naming and structure
- **Never break module boundaries** - respect the polyShape/polyGdal/polyClipper/polyPlot separation
- **Never bypass module qualification** - always use explicit module.function() syntax
- **Never compromise Docker containerization** compatibility or deployment consistency

### **🚀 PERFORMANCE OPTIMIZATION PRIORITIES:**
1. **Use specialized modules** for optimal performance (polyClipper for Boolean operations, polyGdal for format conversion)
2. **Leverage parallel processing** capabilities in volumetric optimization scripts
3. **Maintain efficient memory management** with proper deepcopy() usage for mutable structs
4. **Optimize database queries** using appropriate connection patterns and query optimization
5. **Implement proper caching strategies** for frequently accessed geometric operations and spatial data

This comprehensive development framework ensures consistent, maintainable, and high-performance code that leverages the full power of the modular architecture while maintaining strict adherence to Chilean real estate development requirements and computational geometry best practices.