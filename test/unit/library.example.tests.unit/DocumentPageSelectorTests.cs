using AwesomeAssertions;

using Library.Example.Abstractions;

using NSubstitute;

namespace Library.Example.Tests.Unit;

/// <summary>
/// Exercises selection against the page count reported by the catalog.
/// </summary>
public class DocumentPageSelectorTests
{
    [Fact]
    public async Task SelectAsync_WhenTheCatalogReportsEightPages_ThenSelectsPageEight()
    {
        // Arrange
        var token = TestContext.Current.CancellationToken;
        var catalog = Substitute.For<IDocumentCatalog>();
        catalog.GetPageCountAsync("manual", token).Returns(8);
        var selector = new DocumentPageSelector(catalog);

        // Act
        var pages = await selector.SelectAsync("manual", "8", token);

        // Assert
        pages.Should().Equal([8], "the requested page exists in the catalog's edition of the manual");
    }

    [Fact]
    public async Task SelectAsync_WhenTheCatalogReportsSevenPages_ThenRejectsPageEight()
    {
        // Arrange
        var token = TestContext.Current.CancellationToken;
        var catalog = Substitute.For<IDocumentCatalog>();
        catalog.GetPageCountAsync("manual", token).Returns(7);
        var selector = new DocumentPageSelector(catalog);

        // Act
        var act = async () => await selector.SelectAsync("manual", "8", token);

        // Assert
        await act.Should().ThrowAsync<ArgumentOutOfRangeException>("the requested page is past the end of this edition of the manual");
    }
}
