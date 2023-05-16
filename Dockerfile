# Use the official Julia Docker image as the base
FROM julia:latest

# Set the working directory for the Julia code
# WORKDIR /app

# Copy the rest of your code into the container
COPY secrets.env /app/src/
#COPY /src/script*.* /app/src/


# Install the Julia packages
RUN julia -e 'using Pkg; Pkg.add("DotEnv");' # \
            #  Pkg.add(url="https://github.com/PainterQubits/Devices.jl.git"); \
            #  Pkg.add(url="https://github.com/rjvial/LandValue.git")'


# Set the entry point for the container
#CMD ["julia", "/app/src/script_2A_ejecutaCombinaciones_volumetrica.jl"]
CMD ["julia", "/app/src/basura.jl"]


# Use the official Julia Docker image as the base
#cd C:\Users\rjvia\Documents\Land_engines_code\Julia\LandValue
#docker build -t myimagename .
#docker run myimagename

