namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record CategoryListRequest(string? Search = null, int Page = 1, int PageSize = 50);
