using AHKFlowApp.Application.Abstractions;

namespace AHKFlowApp.API;

internal sealed record DevEnvironment(bool IsDevelopment) : IDevEnvironment;
