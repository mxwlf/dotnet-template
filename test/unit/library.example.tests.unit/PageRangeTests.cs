using AwesomeAssertions;

namespace Library.Example.Tests.Unit;

/// <summary>
/// Tests for the page selection grammar.
/// </summary>
public class PageRangeTests
{
    [Fact]
    public void Parse_WhenRangesOverlap_ThenReturnsEachPageOnceInAscendingOrder()
    {
        // Arrange
        const string expression = " 8, 3 - 5, 1, 4-6, 3, 5-5 ";

        // Act
        var pages = PageRange.Parse(expression, 8);

        // Assert
        pages.Should().Equal([1, 3, 4, 5, 6, 8], "ranges include both endpoints and overlapping selections print a page once");
    }

    [Fact]
    public void Parse_WhenTheRangeCoversEveryRepresentablePage_ThenCanReadOnlyTheFirstPages()
    {
        // Arrange
        const string expression = "1-2147483647";

        // Act
        var pages = PageRange.Parse(expression, int.MaxValue).Take(2);

        // Assert
        pages.Should().Equal([1, 2], "a large valid range can be consumed incrementally");
    }

    [Fact]
    public void Parse_WhenTheFinalPageIsIntMaxValue_ThenStopsAfterTheEndpoint()
    {
        // Arrange
        const string expression = "2147483647,2147483646-2147483647";

        // Act
        var pages = PageRange.Parse(expression, int.MaxValue);

        // Assert
        pages.Should().Equal([int.MaxValue - 1, int.MaxValue], "the largest valid page is returned once and terminates the range");
    }

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData(",1")]
    [InlineData("1,")]
    [InlineData("1,,2")]
    [InlineData("-2")]
    [InlineData("1-")]
    [InlineData("3-2")]
    [InlineData("1-2-3")]
    [InlineData("1,2x")]
    [InlineData("+2")]
    [InlineData("2147483648")]
    public void Parse_WhenAnyTermIsMalformed_ThenRejectsTheExpressionImmediately(string expression)
    {
        // Arrange
        // Act
        Action act = () => PageRange.Parse(expression, 8);

        // Assert
        act.Should().Throw<FormatException>("a malformed term invalidates the whole selection before enumeration starts");
    }

    [Theory]
    [InlineData("0")]
    [InlineData("9")]
    [InlineData("7-9")]
    public void Parse_WhenAPageIsOutsideTheDocument_ThenRejectsTheSelection(string expression)
    {
        // Arrange
        // Act
        Action act = () => PageRange.Parse(expression, 8);

        // Assert
        act.Should().Throw<ArgumentOutOfRangeException>("every selected page must exist in the document");
    }

    [Fact]
    public void Parse_WhenTheDocumentHasNoPages_ThenRejectsThePageCount()
    {
        // Arrange
        // Act
        Action act = static () => PageRange.Parse("1", 0);

        // Assert
        act.Should().Throw<ArgumentOutOfRangeException>().WithParameterName("pageCount");
    }
}
