# syntax=docker/dockerfile:1
ARG DOTNET_SDK=10.0
ARG NGINX=1.27-alpine

FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_SDK} AS build
WORKDIR /src

# Copy solution-level configuration first so restore is cached when source changes
COPY Directory.Build.props Directory.Packages.props ./

# Copy project files preserving directory structure for restore-only layer
COPY src/Backend/AHKFlowApp.Domain/AHKFlowApp.Domain.csproj src/Backend/AHKFlowApp.Domain/
COPY src/Backend/AHKFlowApp.Application/AHKFlowApp.Application.csproj src/Backend/AHKFlowApp.Application/
COPY src/Backend/AHKFlowApp.Infrastructure/AHKFlowApp.Infrastructure.csproj src/Backend/AHKFlowApp.Infrastructure/
COPY src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj src/Backend/AHKFlowApp.API/
COPY src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj src/Frontend/AHKFlowApp.UI.Blazor/

RUN dotnet restore src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj

# Copy remaining source after restore so source-only changes don't bust the restore cache
COPY src/ src/

# Bake local config into appsettings.json BEFORE publish so PWA integrity hashes match
# and service-worker-assets.js excludes the deleted env-specific files.
RUN cp src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Local.json \
       src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.json && \
    rm -f src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Production.json \
          src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Test.json \
          src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json \
          src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.E2E.json \
          src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Local.json \
          src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json.example

RUN dotnet publish src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj \
    -c Release -o /app/publish --no-restore

FROM nginx:${NGINX} AS final
COPY --from=build /app/publish/wwwroot /usr/share/nginx/html
COPY src/Frontend/AHKFlowApp.UI.Blazor/nginx/default.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
