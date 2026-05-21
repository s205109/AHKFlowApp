using FluentValidation;

namespace AHKFlowApp.Application.Validation;

internal static class CategoryRules
{
    public static IRuleBuilderOptions<T, string> ValidCategoryName<T>(this IRuleBuilder<T, string> rule) =>
        rule
            .NotEmpty().WithMessage("Category name is required.")
            .MaximumLength(30).WithMessage("Category name must be 30 characters or fewer.");
}
