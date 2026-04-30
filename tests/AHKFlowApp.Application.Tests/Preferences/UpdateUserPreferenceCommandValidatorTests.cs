using AHKFlowApp.Application.Commands.Preferences;
using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Preferences;

public sealed class UpdateUserPreferenceCommandValidatorTests
{
    private readonly UpdateUserPreferenceCommandValidator _sut = new();

    private static UpdateUserPreferenceCommand Cmd(int rowsPerPage = 10, bool darkMode = false)
        => new(new UpdateUserPreferenceDto(rowsPerPage, darkMode));

    [Theory]
    [InlineData(2)]
    [InlineData(10)]
    [InlineData(25)]
    [InlineData(50)]
    [InlineData(100)]
    public void Validate_WithValidRowsPerPage_Succeeds(int rowsPerPage)
    {
        ValidationResult result = _sut.Validate(Cmd(rowsPerPage: rowsPerPage));

        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData(0)]
    [InlineData(7)]
    [InlineData(200)]
    [InlineData(-1)]
    public void Validate_WithInvalidRowsPerPage_Fails(int rowsPerPage)
    {
        ValidationResult result = _sut.Validate(Cmd(rowsPerPage: rowsPerPage));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Dto.RowsPerPage" &&
            e.ErrorMessage == "RowsPerPage must be 2, 10, 25, 50, or 100.");
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void Validate_WithAnyDarkMode_Succeeds(bool darkMode)
    {
        ValidationResult result = _sut.Validate(Cmd(darkMode: darkMode));

        result.IsValid.Should().BeTrue();
    }
}
