using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Behaviors;
using AHKFlowApp.Application.Commands.Categories;
using AHKFlowApp.Application.Commands.Dev;
using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.Commands.Preferences;
using AHKFlowApp.Application.Commands.Profiles;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Categories;
using AHKFlowApp.Application.Queries.Dashboard;
using AHKFlowApp.Application.Queries.Downloads;
using AHKFlowApp.Application.Queries.Hotkeys;
using AHKFlowApp.Application.Queries.Hotstrings;
using AHKFlowApp.Application.Queries.Preferences;
using AHKFlowApp.Application.Queries.Profiles;
using AHKFlowApp.Application.Services;
using Ardalis.Result;
using FluentValidation;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddScoped(typeof(IUseCase<,>), typeof(ValidatingUseCase<,>));

        services.AddValidatorsFromAssembly(typeof(DependencyInjection).Assembly);

        services
            .AddUseCase<CreateCategoryCommand, Result<CategoryDto>, CreateCategoryCommandHandler>()
            .AddUseCase<UpdateCategoryCommand, Result<CategoryDto>, UpdateCategoryCommandHandler>()
            .AddUseCase<DeleteCategoryCommand, Result, DeleteCategoryCommandHandler>()
            .AddUseCase<ListCategoriesQuery, Result<PagedList<CategoryDto>>, ListCategoriesQueryHandler>()
            .AddUseCase<GetCategoryQuery, Result<CategoryDto>, GetCategoryQueryHandler>()
            .AddUseCase<SeedCategoriesCommand, Result<IReadOnlyList<CategoryDto>>, SeedCategoriesCommandHandler>()
            .AddUseCase<CreateHotstringCommand, Result<HotstringDto>, CreateHotstringCommandHandler>()
            .AddUseCase<UpdateHotstringCommand, Result<HotstringDto>, UpdateHotstringCommandHandler>()
            .AddUseCase<DeleteHotstringCommand, Result, DeleteHotstringCommandHandler>()
            .AddUseCase<BulkDeleteHotstringsCommand, Result<BulkDeleteResultDto>, BulkDeleteHotstringsCommandHandler>()
            .AddUseCase<ListHotstringsQuery, Result<PagedList<HotstringDto>>, ListHotstringsQueryHandler>()
            .AddUseCase<GetHotstringQuery, Result<HotstringDto>, GetHotstringQueryHandler>()
            .AddUseCase<SeedHotstringsCommand, Result<PagedList<HotstringDto>>, SeedHotstringsCommandHandler>()
            .AddUseCase<CreateHotkeyCommand, Result<HotkeyDto>, CreateHotkeyCommandHandler>()
            .AddUseCase<UpdateHotkeyCommand, Result<HotkeyDto>, UpdateHotkeyCommandHandler>()
            .AddUseCase<DeleteHotkeyCommand, Result, DeleteHotkeyCommandHandler>()
            .AddUseCase<BulkDeleteHotkeysCommand, Result<BulkDeleteResultDto>, BulkDeleteHotkeysCommandHandler>()
            .AddUseCase<ListHotkeysQuery, Result<PagedList<HotkeyDto>>, ListHotkeysQueryHandler>()
            .AddUseCase<GetHotkeyQuery, Result<HotkeyDto>, GetHotkeyQueryHandler>()
            .AddUseCase<SeedHotkeysCommand, Result<PagedList<HotkeyDto>>, SeedHotkeysCommandHandler>()
            .AddUseCase<CreateProfileCommand, Result<ProfileDto>, CreateProfileCommandHandler>()
            .AddUseCase<UpdateProfileCommand, Result<ProfileDto>, UpdateProfileCommandHandler>()
            .AddUseCase<DeleteProfileCommand, Result, DeleteProfileCommandHandler>()
            .AddUseCase<ListProfilesQuery, Result<IReadOnlyList<ProfileDto>>, ListProfilesQueryHandler>()
            .AddUseCase<GetProfileQuery, Result<ProfileDto>, GetProfileQueryHandler>()
            .AddUseCase<GetUserPreferenceQuery, Result<UserPreferenceDto>, GetUserPreferenceQueryHandler>()
            .AddUseCase<UpdateUserPreferenceCommand, Result<UserPreferenceDto>, UpdateUserPreferenceCommandHandler>()
            .AddUseCase<GetDashboardStatsQuery, Result<DashboardStatsDto>, GetDashboardStatsQueryHandler>()
            .AddUseCase<GenerateProfileScriptQuery, Result<ProfileScript>, GenerateProfileScriptQueryHandler>()
            .AddUseCase<GetProfileScriptPreviewQuery, Result<ProfileScriptPreviewDto>, GetProfileScriptPreviewQueryHandler>()
            .AddUseCase<GenerateAllProfileScriptsQuery, Result<IReadOnlyList<ProfileScript>>, GenerateAllProfileScriptsQueryHandler>()
            .AddUseCase<SeedAllCommand, Result<SeedAllResultDto>, SeedAllCommandHandler>();

        services.AddSingleton<HeaderTokenRenderer>();
        services.AddSingleton<AhkScriptGenerator>();
        services.AddScoped<ProfileScriptLoader>();

        return services;
    }

    private static IServiceCollection AddUseCase<TRequest, TResult, THandler>(this IServiceCollection services)
        where TRequest : notnull
        where THandler : class, IUseCaseHandler<TRequest, TResult>
    {
        return services.AddScoped<IUseCaseHandler<TRequest, TResult>, THandler>();
    }
}
