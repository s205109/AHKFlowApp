namespace AHKFlowApp.Application.DTOs;

/// <summary>Paginated wrapper for a list response.</summary>
/// <typeparam name="T">Element type.</typeparam>
/// <param name="Items">Page contents.</param>
/// <param name="Page">1-based page number returned.</param>
/// <param name="PageSize">Maximum number of items per page.</param>
/// <param name="TotalCount">Total matching items across all pages.</param>
public sealed record PagedList<T>(
    IReadOnlyList<T> Items,
    int Page,
    int PageSize,
    int TotalCount)
{
    /// <summary>Total number of pages, calculated as <c>ceil(TotalCount / PageSize)</c>.</summary>
    public int TotalPages => PageSize == 0 ? 0 : (int)Math.Ceiling(TotalCount / (double)PageSize);

    /// <summary>True when a next page exists.</summary>
    public bool HasNextPage => Page < TotalPages;

    /// <summary>True when a previous page exists.</summary>
    public bool HasPreviousPage => Page > 1;
}
