using AHKFlowApp.Application.Behaviors;
using FluentAssertions;
using FluentAssertions.Specialized;
using FluentValidation;
using FluentValidation.Results;
using MediatR;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Behaviors;

// Must be internal (not nested) so NSubstitute/Castle.DynamicProxy can proxy IValidator<TestRequest>
internal record TestRequest(string Name) : IRequest<string>;

public sealed class ValidationBehaviorTests
{

    [Fact]
    public async Task Handle_WhenNoValidators_CallsNext()
    {
        // Arrange
        IEnumerable<IValidator<TestRequest>> validators = [];
        var behavior = new ValidationBehavior<TestRequest, string>(validators);
        var request = new TestRequest("test");
        bool nextCalled = false;
        Task<string> next(CancellationToken ct)
        {
            nextCalled = true;
            return Task.FromResult("result");
        }

        // Act
        string result = await behavior.Handle(request, next, CancellationToken.None);

        // Assert
        result.Should().Be("result");
        nextCalled.Should().BeTrue();
    }

    [Fact]
    public async Task Handle_WhenValidationPasses_CallsNext()
    {
        // Arrange
        IValidator<TestRequest> validator = Substitute.For<IValidator<TestRequest>>();
        validator.ValidateAsync(Arg.Any<ValidationContext<TestRequest>>(), Arg.Any<CancellationToken>())
            .Returns(new ValidationResult());

        var behavior = new ValidationBehavior<TestRequest, string>([validator]);
        var request = new TestRequest("valid");
        bool nextCalled = false;
        Task<string> next(CancellationToken ct)
        {
            nextCalled = true;
            return Task.FromResult("result");
        }

        // Act
        string result = await behavior.Handle(request, next, CancellationToken.None);

        // Assert
        result.Should().Be("result");
        nextCalled.Should().BeTrue();
    }

    [Fact]
    public async Task Handle_WhenValidationFails_ThrowsValidationException()
    {
        // Arrange
        var failures = new List<ValidationFailure>
        {
            new("Name", "Name is required")
        };
        IValidator<TestRequest> validator = Substitute.For<IValidator<TestRequest>>();
        validator.ValidateAsync(Arg.Any<ValidationContext<TestRequest>>(), Arg.Any<CancellationToken>())
            .Returns(new ValidationResult(failures));

        var behavior = new ValidationBehavior<TestRequest, string>([validator]);
        var request = new TestRequest("");
        bool nextCalled = false;
        Task<string> next(CancellationToken ct)
        {
            nextCalled = true;
            return Task.FromResult("result");
        }

        // Act
        Func<Task> act = async () => await behavior.Handle(request, next, CancellationToken.None);

        // Assert
        await act.Should().ThrowAsync<ValidationException>()
            .Where(ex => ex.Errors.Any(e => e.ErrorMessage == "Name is required"));
        nextCalled.Should().BeFalse();
    }

    [Fact]
    public async Task Handle_WhenMultipleValidatorsFail_CombinesAllErrors()
    {
        // Arrange
        IValidator<TestRequest> validator1 = Substitute.For<IValidator<TestRequest>>();
        validator1.ValidateAsync(Arg.Any<ValidationContext<TestRequest>>(), Arg.Any<CancellationToken>())
            .Returns(new ValidationResult([new ValidationFailure("Name", "Too short")]));

        IValidator<TestRequest> validator2 = Substitute.For<IValidator<TestRequest>>();
        validator2.ValidateAsync(Arg.Any<ValidationContext<TestRequest>>(), Arg.Any<CancellationToken>())
            .Returns(new ValidationResult([new ValidationFailure("Name", "Invalid chars")]));

        var behavior = new ValidationBehavior<TestRequest, string>([validator1, validator2]);
        static Task<string> next(CancellationToken ct)
        {
            return Task.FromResult("result");
        }

        // Act
        Func<Task> act = async () => await behavior.Handle(new TestRequest("x"), next, CancellationToken.None);

        // Assert
        ExceptionAssertions<ValidationException> ex = await act.Should().ThrowAsync<ValidationException>();
        ex.Which.Errors.Should().HaveCount(2);
    }
}
