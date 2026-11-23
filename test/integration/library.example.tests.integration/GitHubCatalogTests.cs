using Library.Example.Abstractions;

using Microsoft.Extensions.DependencyInjection;

using Xunit;

namespace Library.Example.Tests.Integration;

// Remove alongside the explicit skips after the fixtures are available on public main.
#pragma warning disable xUnit1004

/// <summary>
/// Exercises document selection against the public catalog fixtures on GitHub.
/// </summary>
public sealed class GitHubCatalogTests
{
    private const string AwaitingPublication = "Enable after verifying the fixture JSON on mxwlf/dotnet-template main.";
    private const string FixtureRoot = "https://raw.githubusercontent.com/mxwlf/dotnet-template/main/test/fixtures/document-catalog/";

    /// <summary>
    /// Overlapping ranges include the last page exactly once.
    /// </summary>
    [Fact(Skip = AwaitingPublication)]
    public async Task SelectAsync_WhenDocumentHasEightPages_ThenIncludesPageEight()
    {
        await using var services = Compose("eight-pages");
        var selector = services.GetRequiredService<DocumentPageSelector>();

        var pages = await selector.SelectAsync("document", "8, 3-5, 4", TestContext.Current.CancellationToken);

        Assert.Equal([3, 4, 5, 8], pages);
    }

    /// <summary>
    /// The catalog count determines the upper bound of the selection.
    /// </summary>
    [Fact(Skip = AwaitingPublication)]
    public async Task SelectAsync_WhenDocumentHasSevenPages_ThenRejectsPageEight()
    {
        await using var services = Compose("seven-pages");
        var selector = services.GetRequiredService<DocumentPageSelector>();

        await Assert.ThrowsAsync<ArgumentOutOfRangeException>(
            async () => await selector.SelectAsync("document", "8", TestContext.Current.CancellationToken));
    }

    /// <summary>
    /// Bad metadata and missing documents have distinct, non-transient outcomes.
    /// </summary>
    /// <param name="scenario">The scenario directory to use as the HTTP base address.</param>
    /// <param name="documentId">The catalog entry to request.</param>
    /// <param name="expectedFailure">The failure visible to the caller.</param>
    [Theory(Skip = AwaitingPublication)]
    [InlineData("missing-page-count", "document", DocumentCatalogFailure.InvalidResponse)]
    [InlineData("wrong-page-count-type", "document", DocumentCatalogFailure.InvalidResponse)]
    [InlineData("zero-page-count", "document", DocumentCatalogFailure.InvalidResponse)]
    [InlineData("eight-pages", "absent-document", DocumentCatalogFailure.NotFound)]
    public async Task SelectAsync_WhenLookupFails_ThenReportsCatalogFailure(
        string scenario, string documentId, DocumentCatalogFailure expectedFailure)
    {
        await using var services = Compose(scenario);
        var selector = services.GetRequiredService<DocumentPageSelector>();

        var error = await Assert.ThrowsAsync<DocumentCatalogException>(
            async () => await selector.SelectAsync(documentId, "1", TestContext.Current.CancellationToken));

        Assert.Equal(expectedFailure, error.Failure);
        Assert.False(error.IsTransient);
    }

    private static ServiceProvider Compose(string scenario)
    {
        var services = new ServiceCollection();
        var baseAddress = new Uri(FixtureRoot + scenario + "/");
        services.AddDocumentPageSelection(baseAddress);
        return services.BuildServiceProvider();
    }
}
#pragma warning restore xUnit1004
