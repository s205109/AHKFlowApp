using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Abstractions;

public interface IEntityHistoryRecorder
{
    /// <summary>Stages a before-image of the hotstring aggregate on the tracked context.</summary>
    Task<EntityHistory> RecordHotstringAsync(Hotstring entity, HistoryChangeType changeType, CancellationToken ct);

    /// <summary>Stages a before-image of the hotkey aggregate on the tracked context.</summary>
    Task<EntityHistory> RecordHotkeyAsync(Hotkey entity, HistoryChangeType changeType, CancellationToken ct);
}
