using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record ImportHotstringsCommand(ImportHotstringsRequestDto Input);

public sealed class ImportHotstringsCommandValidator : AbstractValidator<ImportHotstringsCommand>
{
    public ImportHotstringsCommandValidator()
    {
        RuleFor(x => x.Input.Script)
            .Cascade(CascadeMode.Stop)
            .NotEmpty().WithMessage("Script is required.")
            .MaximumLength(HotstringImportRules.MaxScriptLength)
            .WithMessage($"Script must be {HotstringImportRules.MaxScriptLength} characters or fewer.");

        this.AddProfileAssociationRules(
            x => x.Input.AppliesToAllProfiles,
            x => x.Input.ProfileIds);
    }
}

internal sealed class ImportHotstringsCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IUseCaseHandler<ImportHotstringsCommand, Result<HotstringImportResultDto>>
{
    public async Task<Result<HotstringImportResultDto>> ExecuteAsync(
        ImportHotstringsCommand request,
        CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        ImportHotstringsRequestDto input = request.Input;

        IReadOnlyList<HotstringImportRowDto> parsed = AhkHotstringParser.Parse(input.Script);
        if (parsed.Count > HotstringImportRules.MaxRows)
            return Result.Invalid(new ValidationError
            {
                Identifier = "Input.Script",
                ErrorMessage = $"Import supports at most {HotstringImportRules.MaxRows} hotstrings per file.",
            });

        Guid[] distinctProfileIds = input.ProfileIds?.Distinct().ToArray() ?? [];
        if (!input.AppliesToAllProfiles)
        {
            ValidationError? profileError = await OwnedIdsValidation.CheckOwnedIdsAsync(
                db.Profiles, p => p.OwnerOid == ownerOid && distinctProfileIds.Contains(p.Id),
                distinctProfileIds, "ProfileIds", ct);
            if (profileError is not null)
                return Result.Invalid(profileError);
        }

        // Mark in-file repeats (empty existing set); DB collisions are handled by the retry below.
        List<HotstringImportRowDto> final =
            [.. HotstringImportClassifier.MarkDuplicates(parsed, new HashSet<string>())];

        List<(int Index, HotstringImportRowDto Row)> pending =
        [
            .. final.Select((row, index) => (Index: index, Row: row))
                    .Where(x => x.Row.Status is HotstringImportRowStatus.Ready or HotstringImportRowStatus.Warning)
        ];

        List<Hotstring> created = [];
        List<HotstringProfile> createdLinks = [];
        AddEntities(pending);

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            // A trigger already existed (pre-existing or created concurrently). Detach exactly
            // this batch's pending entities, re-query the owner's triggers, drop the
            // now-colliding rows, and re-save the rest.
            foreach (Hotstring hs in created)
                db.Entry(hs).State = EntityState.Detached;
            foreach (HotstringProfile hp in createdLinks)
                db.Entry(hp).State = EntityState.Detached;
            created.Clear();
            createdLinks.Clear();

            HashSet<string> existing = new(
                await db.Hotstrings.Where(h => h.OwnerOid == ownerOid).Select(h => h.Trigger).ToListAsync(ct),
                StringComparer.OrdinalIgnoreCase);

            List<(int Index, HotstringImportRowDto Row)> survivors = [];
            foreach ((int index, HotstringImportRowDto row) in pending)
            {
                if (existing.Contains(row.Trigger))
                    final[index] = row with
                    {
                        Status = HotstringImportRowStatus.Duplicate,
                        Reason = HotstringImportClassifier.DuplicateReason,
                    };
                else
                    survivors.Add((index, row));
            }

            AddEntities(survivors);
            await db.SaveChangesAsync(ct);
        }

        int imported = final.Count(r => r.Status is HotstringImportRowStatus.Ready or HotstringImportRowStatus.Warning);
        int warnings = final.Count(r => r.Status == HotstringImportRowStatus.Warning);

        return Result.Success(new HotstringImportResultDto(imported, warnings, [.. final]));

        void AddEntities(List<(int Index, HotstringImportRowDto Row)> items)
        {
            foreach ((int _, HotstringImportRowDto row) in items)
            {
                var entity = Hotstring.Create(
                    ownerOid, row.Trigger, row.Replacement, description: null,
                    input.AppliesToAllProfiles, row.IsEndingCharacterRequired, row.IsTriggerInsideWord, clock);
                db.Hotstrings.Add(entity);
                created.Add(entity);

                if (!input.AppliesToAllProfiles)
                {
                    foreach (Guid pid in distinctProfileIds)
                    {
                        var link = HotstringProfile.Create(entity.Id, pid);
                        db.HotstringProfiles.Add(link);
                        createdLinks.Add(link);
                    }
                }
            }
        }
    }
}
