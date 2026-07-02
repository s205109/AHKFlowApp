using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Abstractions;

public interface IEntityHistoryRecorder
{
    /// <summary>Stages a before-image of the hotstring aggregate on the tracked context.</summary>
    Task<EntityHistory> RecordHotstringAsync(Hotstring entity, HistoryChangeType changeType, CancellationToken ct);

    /// <summary>Stages before-images of hotstring aggregates on the tracked context.</summary>
    Task<IReadOnlyList<EntityHistory>> RecordHotstringsAsync(
        IReadOnlyCollection<Hotstring> entities,
        HistoryChangeType changeType,
        CancellationToken ct);

    /// <summary>Stages a before-image of the hotkey aggregate on the tracked context.</summary>
    Task<EntityHistory> RecordHotkeyAsync(Hotkey entity, HistoryChangeType changeType, CancellationToken ct);

    /// <summary>Stages before-images of hotkey aggregates on the tracked context.</summary>
    Task<IReadOnlyList<EntityHistory>> RecordHotkeysAsync(
        IReadOnlyCollection<Hotkey> entities,
        HistoryChangeType changeType,
        CancellationToken ct);
}
