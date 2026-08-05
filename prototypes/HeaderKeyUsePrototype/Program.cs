// PROTOTYPE — throwaway TUI shell. Nothing here is meant to ship.
// Run: dotnet run --project prototypes/HeaderKeyUsePrototype
//
// Question: does the agreed parser rule pick exactly the keys a Profile header uses as hotkeys,
// and does the warning sentence read right against real header text?
using HeaderKeyUsePrototype;

const string Bold = "\x1b[1m";
const string Dim = "\x1b[2m";
const string Reset = "\x1b[0m";
const string Yellow = "\x1b[33m";
const string Green = "\x1b[32m";

string[] profileNames = ["Work", "Games", "Writing"];
int[] variants = [0, 1, 2];
bool[] member = [true, true, false];
int focused = 0;

string[] rowKeys = ["CapsLock", "ScrollLock", "C", "NumLock", "F1"];
int rowKeyIndex = 0;

string[] modifierLabels = ["none", "Ctrl", "Ctrl+Alt+Shift"];
int modifierIndex = 0;

bool appliesToAll = false;

// Scripted mode replays one keystroke per character, printing a frame after each. It exists so the
// prototype can be driven without a terminal and the run pasted back as a transcript.
string? script = args.Length > 0 ? args[0] : null;
bool scripted = script is not null;
int scriptPosition = 0;

while (true)
{
    Render();

    char pressed;

    if (scripted)
    {
        if (scriptPosition >= script!.Length)
            break;

        pressed = script[scriptPosition++];
        Console.WriteLine($"{Dim}>>> pressed [{(pressed == ' ' ? "space" : pressed.ToString())}]{Reset}");
    }
    else
    {
        pressed = Console.ReadKey(intercept: true).KeyChar;
    }

    if (pressed is 'q' or 'Q')
        break;

    switch (pressed)
    {
        case '1': focused = 0; break;
        case '2': focused = 1; break;
        case '3': focused = 2; break;
        case 'h': variants[focused] = (variants[focused] + 1) % Fixtures.VariantNames.Length; break;
        case 'k': rowKeyIndex = (rowKeyIndex + 1) % rowKeys.Length; break;
        case 'm': modifierIndex = (modifierIndex + 1) % modifierLabels.Length; break;
        case 'a': appliesToAll = !appliesToAll; break;
        case ' ': member[focused] = !member[focused]; break;
    }
}

void Render()
{
    if (!scripted)
        Console.Clear();
    else
        Console.WriteLine(new string('-', 100));

    Console.WriteLine($"{Bold}Header key use — prototype{Reset}");
    Console.WriteLine($"{Dim}Does a Profile header template already use this row's key?{Reset}");
    Console.WriteLine();

    Console.WriteLine($"{Bold}Hotkey row{Reset}");
    Console.WriteLine($"  key        {rowKeys[rowKeyIndex]}");
    Console.WriteLine($"  modifiers  {modifierLabels[modifierIndex]}   {Dim}(ignored — matching is on the key alone){Reset}");
    Console.WriteLine($"  profiles   {(appliesToAll ? "all profiles" : Membership())}");
    Console.WriteLine();

    Console.WriteLine($"{Bold}Profiles{Reset}");

    for (int i = 0; i < profileNames.Length; i++)
    {
        IReadOnlyList<string> keys = HeaderKeyUses.Parse(Fixtures.Header(variants[i]));
        string marker = i == focused ? ">" : " ";
        string inRow = appliesToAll || member[i] ? "in row" : "      ";
        string used = keys.Count == 0 ? $"{Dim}(uses no keys){Reset}" : string.Join(", ", keys);

        Console.WriteLine($" {marker} {profileNames[i],-8} {Dim}{inRow}{Reset}  {Fixtures.VariantNames[variants[i]],-42} {used}");
    }

    Console.WriteLine();
    Console.WriteLine($"{Bold}Warning{Reset}");

    string? text = HeaderUseText.TextFor(Considered(), rowKeys[rowKeyIndex], Fixtures.Canonicalize);

    Console.WriteLine(text is null
        ? $"  {Green}(none){Reset}"
        : $"  {Yellow}{text}{Reset}");

    Console.WriteLine();
    Console.WriteLine($"{Dim}[1|2|3] focus  [h] header variant  [k] row key  [m] modifiers  [a] all profiles  [space] membership  [q] quit{Reset}");
}

string Membership()
{
    string[] names = [.. profileNames.Where((_, i) => member[i])];
    return names.Length == 0 ? "(none)" : string.Join(", ", names);
}

List<ProfileHeaderUse> Considered()
{
    List<ProfileHeaderUse> uses = [];

    for (int i = 0; i < profileNames.Length; i++)
    {
        if (!appliesToAll && !member[i])
            continue;

        uses.Add(new ProfileHeaderUse(profileNames[i], HeaderKeyUses.Parse(Fixtures.Header(variants[i]))));
    }

    return uses;
}
