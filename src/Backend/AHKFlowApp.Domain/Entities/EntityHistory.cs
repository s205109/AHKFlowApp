using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Domain.Entities;

public sealed class EntityHistory
{
    private EntityHistory()
    {
        SnapshotJson = string.Empty;
    }

    public Guid Id { get; private set; }
    public Guid OwnerOid { get; private set; }
    public TrackedEntityType EntityType { get; private set; }
    public Guid EntityId { get; private set; }
    public int Version { get; private set; }
    public HistoryChangeType ChangeType { get; private set; }
    public int SchemaVersion { get; private set; }
    public DateTimeOffset CapturedAt { get; private set; }
    public string SnapshotJson { get; private set; }

    public static EntityHistory Create(
        Guid ownerOid,
        TrackedEntityType entityType,
        Guid entityId,
        int version,
        HistoryChangeType changeType,
        int schemaVersion,
        string snapshotJson,
        TimeProvider clock)
        => new()
        {
            Id = Guid.NewGuid(),
            OwnerOid = ownerOid,
            EntityType = entityType,
            EntityId = entityId,
            Version = version,
            ChangeType = changeType,
            SchemaVersion = schemaVersion,
            SnapshotJson = snapshotJson,
            CapturedAt = clock.GetUtcNow(),
        };

    public void ReassignVersion(int version) => Version = version;
}
