# syntax=docker/dockerfile:1
ARG DOTNET_SDK=10.0
ARG NGINX=1.27-alpine

FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_SDK} AS build
WORKDIR /src
COPY . .

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

RUN dotnet restore src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj
RUN dotnet publish src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj \
    -c Release -o /app/publish --no-restore

FROM nginx:${NGINX} AS final
COPY --from=build /app/publish/wwwroot /usr/share/nginx/html
COPY src/Frontend/AHKFlowApp.UI.Blazor/nginx/default.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
