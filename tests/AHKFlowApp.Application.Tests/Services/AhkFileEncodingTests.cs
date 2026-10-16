using AHKFlowApp.Application.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class AhkFileEncodingTests
{
    private static readonly byte[] Utf8Bom = [0xEF, 0xBB, 0xBF];

    [Fact]
    public void GetBytes_NonAsciiText_WritesUtf8AfterTheMark()
    {
        // The arrow is U+2192, which UTF-8 writes as E2 86 92.
        byte[] bytes = AhkFileEncoding.GetBytes("->" + (char)0x2192);

        bytes.Should().Equal(0xEF, 0xBB, 0xBF, (byte)'-', (byte)'>', 0xE2, 0x86, 0x92);
    }

    [Fact]
    public void GetBytes_EmptyScript_ReturnsOnlyTheMark()
    {
        byte[] bytes = AhkFileEncoding.GetBytes("");

        bytes.Should().Equal(Utf8Bom);
    }
}
