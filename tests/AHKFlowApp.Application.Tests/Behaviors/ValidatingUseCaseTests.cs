using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Behaviors;
using FluentAssertions;
using FluentAssertions.Specialized;
using FluentValidation;
using FluentValidation.Results;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Behaviors;

// Must be internal (not nested) so NSubstitute/Castle.DynamicProxy can proxy IValidator<TestRequest>
internal sealed record TestRequest(string Name);

public sealed class ValidatingUseCaseTests
{
    [Fact]
    public async Task ExecuteAsync_WhenNoValidators_CallsInner()
    {
        // Arrange
        IEnumerable<IValidator<TestRequest>> validators = [];
        IUseCaseHandler<TestRequest, string> inner = Substitute.For<IUseCaseHandler<TestRequest, string>>();
        inner.ExecuteAsync(Arg.Any<TestRequest>(), Arg.Any<CancellationToken>())
            .Returns(Task.FromResult("result"));
        var useCase = new ValidatingUseCase<TestRequest, string>(validators, inner);
        var request = new TestRequest("test");

        // Act
        string result = await useCase.ExecuteAsync(request, CancellationToken.None);

        // Assert
        result.Should().Be("result");
        await inner.Received(1).ExecuteAsync(request, Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task ExecuteAsync_WhenValidationPasses_CallsInner()
    {
        // Arrange
        IValidator<TestRequest> validator = Substitute.For<IValidator<TestRequest>>();
        validator.ValidateAsync(Arg.Any<ValidationContext<TestRequest>>(), Arg.Any<CancellationToken>())
            .Returns(new ValidationResult());

        IUseCaseHandler<TestRequest, string> inner = Substitute.For<IUseCaseHandler<TestRequest, string>>();
        inner.ExecuteAsync(Arg.Any<TestRequest>(), Arg.Any<CancellationToken>())
            .Returns(Task.FromResult("result"));
        var useCase = new ValidatingUseCase<TestRequest, string>([validator], inner);
        var request = new TestRequest("valid");

        // Act
        string result = await useCase.ExecuteAsync(request, CancellationToken.None);

        // Assert
        result.Should().Be("result");
        await inner.Received(1).ExecuteAsync(request, Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task ExecuteAsync_WhenValidationFails_ThrowsValidationException()
    {
        // Arrange
        var failures = new List<ValidationFailure>
        {
            new("Name", "Name is required")
        };
        IValidator<TestRequest> validator = Substitute.For<IValidator<TestRequest>>();
        validator.ValidateAsync(Arg.Any<ValidationContext<TestRequest>>(), Arg.Any<CancellationToken>())
            .Returns(new ValidationResult(failures));

        IUseCaseHandler<TestRequest, string> inner = Substitute.For<IUseCaseHandler<TestRequest, string>>();
        inner.ExecuteAsync(Arg.Any<TestRequest>(), Arg.Any<CancellationToken>())
            .Returns(Task.FromResult("result"));
        var useCase = new ValidatingUseCase<TestRequest, string>([validator], inner);
        var request = new TestRequest("");

        // Act
        Func<Task> act = async () => await useCase.ExecuteAsync(request, CancellationToken.None);

        // Assert
        await act.Should().ThrowAsync<ValidationException>()
            .Where(ex => ex.Errors.Any(e => e.ErrorMessage == "Name is required"));
        await inner.DidNotReceive().ExecuteAsync(Arg.Any<TestRequest>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task ExecuteAsync_WhenMultipleValidatorsFail_CombinesAllErrors()
    {
        // Arrange
        IValidator<TestRequest> validator1 = Substitute.For<IValidator<TestRequest>>();
        validator1.ValidateAsync(Arg.Any<ValidationContext<TestRequest>>(), Arg.Any<CancellationToken>())
            .Returns(new ValidationResult([new ValidationFailure("Name", "Too short")]));

        IValidator<TestRequest> validator2 = Substitute.For<IValidator<TestRequest>>();
        validator2.ValidateAsync(Arg.Any<ValidationContext<TestRequest>>(), Arg.Any<CancellationToken>())
            .Returns(new ValidationResult([new ValidationFailure("Name", "Invalid chars")]));

        IUseCaseHandler<TestRequest, string> inner = Substitute.For<IUseCaseHandler<TestRequest, string>>();
        inner.ExecuteAsync(Arg.Any<TestRequest>(), Arg.Any<CancellationToken>())
            .Returns(Task.FromResult("result"));
        var useCase = new ValidatingUseCase<TestRequest, string>([validator1, validator2], inner);

        // Act
        Func<Task> act = async () => await useCase.ExecuteAsync(new TestRequest("x"), CancellationToken.None);

        // Assert
        ExceptionAssertions<ValidationException> ex = await act.Should().ThrowAsync<ValidationException>();
        ex.Which.Errors.Should().HaveCount(2);
    }
}
