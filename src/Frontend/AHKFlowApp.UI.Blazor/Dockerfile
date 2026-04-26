# syntax=docker/dockerfile:1
ARG DOTNET_SDK=10.0
ARG NGINX=1.27-alpine

FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_SDK} AS build
WORKDIR /src
COPY . .
RUN dotnet restore src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj
RUN dotnet publish src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj \
    -c Release -o /app/publish --no-restore
# Blazor-Environment header doesn't apply to standalone WASM static files; bake local config directly
RUN cp /app/publish/wwwroot/appsettings.Local.json /app/publish/wwwroot/appsettings.json

FROM nginx:${NGINX} AS final
COPY --from=build /app/publish/wwwroot /usr/share/nginx/html
COPY src/Frontend/AHKFlowApp.UI.Blazor/nginx/default.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
