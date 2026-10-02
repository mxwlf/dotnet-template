#:package Microsoft.CodeAnalysis.CSharp@5.0.0
// Regenerates eng/analyzers/all-rules.globalconfig: one explicit entry per rule, for every
// analyzer every project in this repository loads.
//
// WHY A GENERATED FILE RATHER THAN A BULK SEVERITY ENTRY
// -----------------------------------------------------
// Neither `dotnet_analyzer_diagnostic.severity` nor `dotnet_analyzer_diagnostic.category-X.severity`
// switches on a rule its analyzer ships disabled; both only re-rank rules that are already on.
// Verified: RCS1007 stays silent under the global bulk entry and fires under an explicit
// `dotnet_diagnostic.RCS1007.severity` entry. That is also why <AnalysisMode>All</AnalysisMode> is
// implemented by the SDK as 281 explicit CA entries rather than one line. So "every rule on" is
// reachable only by naming every rule, and naming ~1,300 rules by hand is not maintainable.
//
// Usage, from the repository root:
//     dotnet run eng/analyzers/sync-rules.cs             # rewrite the globalconfig
//     dotnet run eng/analyzers/sync-rules.cs --check     # fail if it is stale (for CI)
using System.Diagnostics;
using System.Reflection;
using System.Text;
using System.Text.Json;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Diagnostics;

var repoRoot = FindRepoRoot();
var output = Path.Combine(repoRoot, "eng", "analyzers", "all-rules.globalconfig");
var check = args.Contains("--check");

// Every project, so test-only analyzers (xunit, NSubstitute) are covered too.
var projects = Directory.EnumerateFiles(Path.Combine(repoRoot, "src"), "*.csproj", SearchOption.AllDirectories)
    .Concat(Directory.EnumerateFiles(Path.Combine(repoRoot, "test"), "*.csproj", SearchOption.AllDirectories))
    .OrderBy(p => p, StringComparer.Ordinal)
    .ToArray();

var assemblies = new SortedSet<string>(StringComparer.Ordinal);
foreach (var project in projects)
{
    // Package analyzers land in ResolvedAnalyzers, SDK ones in Analyzer. Both are needed, and
    // ResolvePackageAssets has to run first or ResolvedAnalyzers comes back empty.
    foreach (var item in new[] { "ResolvedAnalyzers", "Analyzer" })
    {
        foreach (var path in MSBuildItem(project, item))
        {
            assemblies.Add(path);
        }
    }
}

var rules = new Dictionary<string, (DiagnosticSeverity Severity, string Title, string Category, bool OnByDefault)>(StringComparer.Ordinal);
var skipped = new List<string>();

foreach (var path in assemblies)
{
    Assembly assembly;
    try { assembly = Assembly.LoadFrom(path); }
    catch { skipped.Add(Path.GetFileName(path)); continue; }

    Type[] types;
    try { types = assembly.GetTypes(); }
    catch (ReflectionTypeLoadException e) { types = e.Types.Where(t => t is not null).ToArray()!; }

    var found = 0;
    foreach (var type in types)
    {
        if (type is null || type.IsAbstract || !typeof(DiagnosticAnalyzer).IsAssignableFrom(type)) continue;
        if (type.GetCustomAttributes<DiagnosticAnalyzerAttribute>().All(a => !a.Languages.Contains(LanguageNames.CSharp))) continue;

        DiagnosticAnalyzer instance;
        try { instance = (DiagnosticAnalyzer)Activator.CreateInstance(type, nonPublic: true)!; }
        catch { continue; }

        foreach (var d in instance.SupportedDiagnostics)
        {
            rules[d.Id] = (d.DefaultSeverity, d.Title.ToString(), d.Category ?? "", d.IsEnabledByDefault);
            found++;
        }
    }

    if (found == 0) skipped.Add(Path.GetFileName(path));
}

var text = Render(rules, projects.Length, assemblies.Count, skipped);

if (check)
{
    var existing = File.Exists(output) ? File.ReadAllText(output) : "";
    if (existing.Replace("\r\n", "\n") == text.Replace("\r\n", "\n"))
    {
        Console.WriteLine($"all-rules.globalconfig is current ({rules.Count} rules).");
        return 0;
    }

    Console.Error.WriteLine("all-rules.globalconfig is stale. Run: dotnet run eng/analyzers/sync-rules.cs");
    return 1;
}

File.WriteAllText(output, text);
Console.WriteLine($"Wrote {rules.Count} rules from {assemblies.Count} analyzer assemblies across {projects.Length} projects.");
return 0;

static string Render(
    Dictionary<string, (DiagnosticSeverity Severity, string Title, string Category, bool OnByDefault)> rules,
    int projectCount,
    int assemblyCount,
    List<string> skipped)
{
    var byPrefix = rules
        .GroupBy(r => new string(r.Key.TakeWhile(char.IsLetter).ToArray()))
        .OrderBy(g => g.Key, StringComparer.Ordinal);

    var sb = new StringBuilder();
    sb.Append("""
        # GENERATED FILE - DO NOT EDIT BY HAND.
        #
        # Regenerate with, from the repository root:
        #     dotnet run eng/analyzers/sync-rules.cs
        #
        # Every analyzer rule every project in this repository loads, each named explicitly, because
        # bulk severity entries do not switch on a rule its analyzer ships disabled - only an explicit
        # per-rule entry does. See the header of sync-rules.cs for the evidence.
        #
        # Severity is `warning`, which $(TreatWarningsAsErrors) turns into an error in Release - so
        # Release and CI hold the strict bar while a Debug build still only warns. Rules whose own
        # default is Error keep `error`, so that nothing here quietly downgrades a rule.
        #
        # THIS FILE IS NOT WHERE EXCEPTIONS GO. A global config loses to .editorconfig for any file
        # .editorconfig matches, so every relaxation belongs in the root .editorconfig (or
        # test/.editorconfig) next to the reason it exists. Editing this file instead means the next
        # regeneration silently reverts it.

        is_global = true

        """);

    sb.Append($"# {rules.Count} rules from {assemblyCount} analyzer assemblies across {projectCount} projects.\n");
    if (skipped.Count > 0)
    {
        sb.Append("# Assemblies contributing no C# rules (source generators, code-fix-only, or built against a\n");
        sb.Append("# different Microsoft.CodeAnalysis than this script loads - IDE* rules are covered by the\n");
        sb.Append("# category-Style entry in .editorconfig instead):\n");
        foreach (var s in skipped.Distinct().OrderBy(x => x, StringComparer.Ordinal))
        {
            sb.Append($"#   {s}\n");
        }
    }

    foreach (var group in byPrefix)
    {
        var onCount = group.Count(r => r.Value.OnByDefault);
        sb.Append($"\n# {group.Key}: {group.Count()} rules ({group.Count() - onCount} of them shipped disabled by default).\n");
        foreach (var rule in group.OrderBy(r => r.Key, StringComparer.Ordinal))
        {
            var severity = rule.Value.Severity == DiagnosticSeverity.Error ? "error" : "warning";
            sb.Append($"dotnet_diagnostic.{rule.Key}.severity = {severity}\n");
        }
    }

    return sb.ToString();
}

static IEnumerable<string> MSBuildItem(string project, string item)
{
    var psi = new ProcessStartInfo("dotnet")
    {
        RedirectStandardOutput = true,
        RedirectStandardError = true,
    };
    psi.ArgumentList.Add("msbuild");
    psi.ArgumentList.Add(project);
    psi.ArgumentList.Add("-t:ResolvePackageAssets");
    psi.ArgumentList.Add($"-getItem:{item}");
    psi.ArgumentList.Add("-p:Configuration=Release");

    using var process = Process.Start(psi)!;
    var stdout = process.StandardOutput.ReadToEnd();
    process.WaitForExit();
    if (process.ExitCode != 0) yield break;

    JsonDocument document;
    try { document = JsonDocument.Parse(stdout); }
    catch { yield break; }

    using (document)
    {
        if (!document.RootElement.TryGetProperty("Items", out var items)) yield break;
        if (!items.TryGetProperty(item, out var entries)) yield break;
        foreach (var entry in entries.EnumerateArray())
        {
            if (entry.TryGetProperty("FullPath", out var full) && full.GetString() is { } value)
            {
                yield return value;
            }
        }
    }
}

static string FindRepoRoot()
{
    var dir = Directory.GetCurrentDirectory();
    while (dir is not null && !File.Exists(Path.Combine(dir, "Directory.Build.props")))
    {
        dir = Path.GetDirectoryName(dir);
    }
    return dir ?? throw new InvalidOperationException("Could not locate the repository root.");
}
