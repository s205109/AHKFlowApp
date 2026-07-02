using AHKFlowApp.Application.Abstractions;
using FluentValidation;

namespace AHKFlowApp.Application.Behaviors;

// Deliberately throws ValidationException — caught at the app boundary
// in GlobalExceptionMiddleware and converted to 400 ProblemDetails.
// This is NOT flow-control abuse; it is a single structured boundary crossing.
internal sealed class ValidatingUseCase<TRequest, TResult>(
    IEnumerable<IValidator<TRequest>> validators,
    IUseCaseHandler<TRequest, TResult> inner)
    : IUseCase<TRequest, TResult>
    where TRequest : notnull
{
    public async Task<TResult> ExecuteAsync(TRequest request, CancellationToken ct)
    {
        if (!validators.Any())
            return await inner.ExecuteAsync(request, ct);

        var context = new ValidationContext<TRequest>(request);

        FluentValidation.Results.ValidationResult[] results = await Task.WhenAll(
            validators.Select(v => v.ValidateAsync(context, ct)));

        List<FluentValidation.Results.ValidationFailure> failures = [.. results
            .SelectMany(r => r.Errors)
            .Where(f => f is not null)];

        if (failures.Count > 0)
            throw new ValidationException(failures);

        return await inner.ExecuteAsync(request, ct);
    }
}
