using System.Text.Json;
using AHKFlowApp.CLI.Services;

namespace AHKFlowApp.CLI.Output;

public static class HotstringJsonFormatter
{
    private static readonly JsonSerializerOptions Options = new(JsonSerializerOptions.Web)
    {
        WriteIndented = true,
    };

    public static void WriteSingle(TextWriter writer, HotstringDto dto)
    {
        writer.WriteLine(JsonSerializer.Serialize(dto, Options));
    }

    public static void WritePage(TextWriter writer, PagedList<HotstringDto> page)
    {
        writer.WriteLine(JsonSerializer.Serialize(page, Options));
    }
}
