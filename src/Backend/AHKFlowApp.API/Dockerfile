# syntax=docker/dockerfile:1.7

# base — runtime image used by VS fast-mode debug (commandName: Docker)
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
WORKDIR /app
EXPOSE 8080
# Serilog file sink writes to /app/AppData/Logs at startup;
# create the directory as root and hand it to the non-root user before dropping privileges.
RUN mkdir -p /app/AppData/Logs && chown -R $APP_UID:$APP_UID /app/AppData
USER $APP_UID

# build — restore + compile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src

# Copy solution-level files first for layer caching
COPY ["Directory.Build.props", "Directory.Packages.props", "./"]

# Copy csproj files only — restore layer caches until a csproj changes
COPY ["src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj", "src/Backend/AHKFlowApp.API/"]
COPY ["src/Backend/AHKFlowApp.Application/AHKFlowApp.Application.csproj", "src/Backend/AHKFlowApp.Application/"]
COPY ["src/Backend/AHKFlowApp.Domain/AHKFlowApp.Domain.csproj", "src/Backend/AHKFlowApp.Domain/"]
COPY ["src/Backend/AHKFlowApp.Infrastructure/AHKFlowApp.Infrastructure.csproj", "src/Backend/AHKFlowApp.Infrastructure/"]
RUN dotnet restore "src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj"

COPY . .
WORKDIR "/src/src/Backend/AHKFlowApp.API"
# MinVerSkip=true: .git/ is excluded from build context (.dockerignore), so MinVer cannot
# read tags. Skipping it prevents MINVER0001 — which would fail the build under
# TreatWarningsAsErrors=true. Local dev containers don't need real versions; CI/CD owns that.
RUN dotnet build "AHKFlowApp.API.csproj" \
    -c $BUILD_CONFIGURATION \
    -o /app/build \
    --no-restore \
    /p:MinVerSkip=true

# publish — produce final binaries
FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "AHKFlowApp.API.csproj" \
    -c $BUILD_CONFIGURATION \
    -o /app/publish \
    --no-restore \
    /p:UseAppHost=false \
    /p:MinVerSkip=true

# final — runtime image used by docker compose / production
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "AHKFlowApp.API.dll"]
