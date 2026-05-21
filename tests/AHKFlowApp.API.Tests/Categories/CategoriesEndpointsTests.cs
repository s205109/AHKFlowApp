using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Categories;

[Collection("WebApi")]
public sealed class CategoriesEndpointsTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.WithTestAuth(b => b.WithOid(oid ?? Guid.NewGuid())).CreateClient();

    [Fact]
    public async Task GET_list_seeds_eight_defaults_on_first_call()
    {
        using HttpClient client = CreateAuthed(Guid.NewGuid());

        HttpResponseMessage response = await client.GetAsync("/api/v1/categories");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<CategoryDto>? body = await response.Content.ReadFromJsonAsync<PagedList<CategoryDto>>();
        body!.TotalCount.Should().Be(8);
    }

    [Fact]
    public async Task GET_list_search_returns_matching_items()
    {
        using HttpClient client = CreateAuthed(Guid.NewGuid());
        await client.GetAsync("/api/v1/categories"); // trigger seed

        HttpResponseMessage response = await client.GetAsync("/api/v1/categories?search=email");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<CategoryDto>? body = await response.Content.ReadFromJsonAsync<PagedList<CategoryDto>>();
        body!.Items.Should().ContainSingle().Which.Name.Should().BeEquivalentTo("Email", because: "email is case-insensitive");
    }

    [Fact]
    public async Task GET_list_pagination_returns_correct_slice()
    {
        using HttpClient client = CreateAuthed(Guid.NewGuid());
        await client.GetAsync("/api/v1/categories"); // trigger seed

        HttpResponseMessage response = await client.GetAsync("/api/v1/categories?page=2&pageSize=3");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<CategoryDto>? body = await response.Content.ReadFromJsonAsync<PagedList<CategoryDto>>();
        body!.Items.Should().HaveCount(3);
        body.Page.Should().Be(2);
        body.PageSize.Should().Be(3);
        body.TotalCount.Should().Be(8);
    }

    [Fact]
    public async Task GET_list_pageSize_too_large_returns_400()
    {
        using HttpClient client = CreateAuthed(Guid.NewGuid());

        HttpResponseMessage response = await client.GetAsync("/api/v1/categories?pageSize=300");

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task GET_list_second_call_does_not_reseed()
    {
        var oid = Guid.NewGuid();
        using HttpClient client = CreateAuthed(oid);

        PagedList<CategoryDto>? first = await (await client.GetAsync("/api/v1/categories"))
            .Content.ReadFromJsonAsync<PagedList<CategoryDto>>();

        PagedList<CategoryDto>? second = await (await client.GetAsync("/api/v1/categories"))
            .Content.ReadFromJsonAsync<PagedList<CategoryDto>>();

        second!.TotalCount.Should().Be(first!.TotalCount);
    }

    [Fact]
    public async Task GET_list_after_deleting_all_returns_zero_and_does_not_reseed()
    {
        var oid = Guid.NewGuid();
        using HttpClient client = CreateAuthed(oid);

        // Seed defaults
        PagedList<CategoryDto>? seeded = await (await client.GetAsync("/api/v1/categories"))
            .Content.ReadFromJsonAsync<PagedList<CategoryDto>>();
        seeded!.TotalCount.Should().Be(8);

        // Delete all eight
        foreach (CategoryDto item in seeded.Items)
            await client.DeleteAsync($"/api/v1/categories/{item.Id}");

        // Get remaining pages too if needed (we seeded exactly 8, page 1 of pageSize=50 covers all)
        // Now list again — seed marker prevents re-seeding
        PagedList<CategoryDto>? after = await (await client.GetAsync("/api/v1/categories"))
            .Content.ReadFromJsonAsync<PagedList<CategoryDto>>();

        after!.TotalCount.Should().Be(0);
    }

    [Fact]
    public async Task POST_creates_category_returns_201_with_location()
    {
        using HttpClient client = CreateAuthed(Guid.NewGuid());

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/categories", new CreateCategoryDto("Work"));

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        response.Headers.Location.Should().NotBeNull();

        CategoryDto? body = await response.Content.ReadFromJsonAsync<CategoryDto>();
        body!.Name.Should().Be("Work");
    }

    [Fact]
    public async Task POST_duplicate_name_returns_409()
    {
        using HttpClient client = CreateAuthed(Guid.NewGuid());
        await client.PostAsJsonAsync("/api/v1/categories", new CreateCategoryDto("Work"));

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/categories", new CreateCategoryDto("Work"));

        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task POST_empty_name_returns_400()
    {
        using HttpClient client = CreateAuthed(Guid.NewGuid());

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/categories", new CreateCategoryDto(""));

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task PUT_updates_name_returns_200()
    {
        using HttpClient client = CreateAuthed(Guid.NewGuid());
        HttpResponseMessage created = await client.PostAsJsonAsync(
            "/api/v1/categories", new CreateCategoryDto("Work"));
        CategoryDto p = (await created.Content.ReadFromJsonAsync<CategoryDto>())!;

        HttpResponseMessage response = await client.PutAsJsonAsync(
            $"/api/v1/categories/{p.Id}", new UpdateCategoryDto("Personal"));

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        CategoryDto updated = (await response.Content.ReadFromJsonAsync<CategoryDto>())!;
        updated.Name.Should().Be("Personal");
    }

    [Fact]
    public async Task PUT_nonexistent_id_returns_404()
    {
        using HttpClient client = CreateAuthed(Guid.NewGuid());

        HttpResponseMessage response = await client.PutAsJsonAsync(
            $"/api/v1/categories/{Guid.NewGuid()}", new UpdateCategoryDto("X"));

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task PUT_duplicate_name_returns_409()
    {
        using HttpClient client = CreateAuthed(Guid.NewGuid());
        await client.PostAsJsonAsync("/api/v1/categories", new CreateCategoryDto("Work"));
        HttpResponseMessage created = await client.PostAsJsonAsync(
            "/api/v1/categories", new CreateCategoryDto("Personal"));
        CategoryDto p = (await created.Content.ReadFromJsonAsync<CategoryDto>())!;

        HttpResponseMessage response = await client.PutAsJsonAsync(
            $"/api/v1/categories/{p.Id}", new UpdateCategoryDto("Work"));

        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task DELETE_returns_204()
    {
        using HttpClient client = CreateAuthed(Guid.NewGuid());
        HttpResponseMessage created = await client.PostAsJsonAsync(
            "/api/v1/categories", new CreateCategoryDto("ToDelete"));
        CategoryDto p = (await created.Content.ReadFromJsonAsync<CategoryDto>())!;

        HttpResponseMessage response = await client.DeleteAsync($"/api/v1/categories/{p.Id}");

        response.StatusCode.Should().Be(HttpStatusCode.NoContent);
    }

    [Fact]
    public async Task DELETE_nonexistent_id_returns_404()
    {
        using HttpClient client = CreateAuthed(Guid.NewGuid());

        HttpResponseMessage response = await client.DeleteAsync($"/api/v1/categories/{Guid.NewGuid()}");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GET_list_unauthenticated_returns_401()
    {
        using HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/categories");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task GET_list_without_scope_returns_403()
    {
        using HttpClient client = _factory.WithTestAuth(b =>
            b.WithOid(Guid.NewGuid()).WithoutScope()).CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/categories");

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    public void Dispose() => _factory.Dispose();
}
