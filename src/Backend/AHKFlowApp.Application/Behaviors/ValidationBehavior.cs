using FluentValidation;
using MediatR;

namespace AHKFlowApp.Application.Behaviors;

// Deliberately throws ValidationException — caught at the app boundary
// in GlobalExceptionMiddleware and converted to 400 ProblemDetails.
// This is NOT flow-control abuse; it is a single structured boundary crossing.
internal sealed class ValidationBehavior<TRequest, TResponse>(
    IEnumerable<IValidator<TRequest>> validators)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken ct)
    {
        if (!validators.Any())
            return await next(ct);

        var context = new ValidationContext<TRequest>(request);

        var failures = validators
            .Select(v => v.Validate(context))
            .SelectMany(r => r.Errors)
            .Where(f => f is not null)
            .ToList();

        if (failures.Count > 0)
            throw new ValidationException(failures);

        return await next(ct);
    }
}
