using System.Net;

using AwesomeAssertions;

using Library.Example.Abstractions;

using Microsoft.Extensions.DependencyInjection;

namespace Library.Example.Tests.Unit;

/// <summary>
/// Exercises the catalog's HTTP client and resilience policy through dependency injection.
/// </summary>
public class HttpDocumentCatalogTests
{
    [Fact]
    public async Task GetPageCountAsync_WhenMetadataExists_ThenReadsTheJsonFileUnderTheConfiguredDirectory()
    {
        // Arrange
        using var transport = new ScriptedHandler(static _ => ScriptedHandler.JsonResponse("""{"pageCount":8}"""));
        await using var services = transport.Compose();
        var catalog = services.GetRequiredService<IDocumentCatalog>();

        // Act
        var count = await catalog.GetPageCountAsync("manual", TestContext.Current.CancellationToken);

        // Assert
        count.Should().Be(8, "the metadata declares eight pages");
        transport.Method.Should().Be(HttpMethod.Get, "a lookup only reads document metadata");
        transport.RequestUri.Should().Be(new Uri(ScriptedHandler.ScenarioDirectory, "manual.json"), "the document belongs to the configured scenario directory");
        transport.Attempts.Should().Be(1, "the first request succeeded");
    }

    [Theory]
    [InlineData(HttpStatusCode.NotFound, DocumentCatalogFailure.NotFound)]
    [InlineData(HttpStatusCode.Forbidden, DocumentCatalogFailure.Rejected)]
    public async Task GetPageCountAsync_WhenTheServerRejectsTheLookup_ThenReportsTheReasonAfterOneRequest(
        HttpStatusCode statusCode, DocumentCatalogFailure expectedFailure)
    {
        // Arrange
        using var transport = new ScriptedHandler(_ => new HttpResponseMessage(statusCode));
        await using var services = transport.Compose();
        var catalog = services.GetRequiredService<IDocumentCatalog>();

        // Act
        var lookup = async () => await catalog.GetPageCountAsync("manual", TestContext.Current.CancellationToken);

        // Assert
        var error = await lookup.Should().ThrowAsync<DocumentCatalogException>("the caller handles catalog failures through the port");
        error.Which.Failure.Should().Be(expectedFailure, "a missing document and a denied lookup have different remedies");
        error.Which.IsTransient.Should().BeFalse("the same request would still be rejected");
        transport.Attempts.Should().Be(1, "the client should surface this response immediately");
    }

    [Theory]
    [InlineData("{")]
    [InlineData("{}")]
    [InlineData("null")]
    [InlineData("""{"pageCount":"eight"}""")]
    [InlineData("""{"pageCount":0}""")]
    [InlineData("""{"pageCount":-1}""")]
    [InlineData("""{"pageCount":1.5}""")]
    public async Task GetPageCountAsync_WhenMetadataHasNoUsablePageCount_ThenReportsAnInvalidResponse(string json)
    {
        // Arrange
        using var transport = new ScriptedHandler(_ => ScriptedHandler.JsonResponse(json));
        await using var services = transport.Compose();
        var catalog = services.GetRequiredService<IDocumentCatalog>();

        // Act
        var lookup = async () => await catalog.GetPageCountAsync("manual", TestContext.Current.CancellationToken);

        // Assert
        var error = await lookup.Should().ThrowAsync<DocumentCatalogException>("page selection needs a positive integer page count");
        error.Which.Failure.Should().Be(DocumentCatalogFailure.InvalidResponse, "a successful HTTP status does not validate the metadata");
        error.Which.IsTransient.Should().BeFalse("retrying cannot repair this file");
        transport.Attempts.Should().Be(1, "invalid metadata needs correction by the publisher");
    }

    [Fact]
    public async Task GetPageCountAsync_WhenMetadataExceedsTheResponseLimit_ThenRejectsTheOversizedFile()
    {
        // Arrange
        var json = new string(' ', 64 * 1024) + """{"pageCount":8}""";
        using var transport = new ScriptedHandler(_ => ScriptedHandler.JsonResponse(json));
        await using var services = transport.Compose();
        var catalog = services.GetRequiredService<IDocumentCatalog>();

        // Act
        var lookup = async () => await catalog.GetPageCountAsync("manual", TestContext.Current.CancellationToken);

        // Assert
        var error = await lookup.Should().ThrowAsync<DocumentCatalogException>("document metadata is limited to 64 KiB");
        error.Which.Failure.Should().Be(DocumentCatalogFailure.InvalidResponse, "a well-formed but oversized response exceeds the catalog contract");
        transport.Attempts.Should().Be(1, "the payload would still exceed the limit on a retry");
    }

    [Fact]
    public async Task GetPageCountAsync_WhenTheIdentifierEscapesTheDirectory_ThenRejectsItBeforeSending()
    {
        // Arrange
        using var transport = new ScriptedHandler(static _ => ScriptedHandler.JsonResponse("""{"pageCount":8}"""));
        await using var services = transport.Compose();
        var catalog = services.GetRequiredService<IDocumentCatalog>();

        // Act
        var lookup = async () => await catalog.GetPageCountAsync("../another", TestContext.Current.CancellationToken);

        // Assert
        await lookup.Should().ThrowAsync<ArgumentException>("the document must be a single identifier under the configured directory");
        transport.Attempts.Should().Be(0, "an invalid identifier cannot be used to address the catalog");
    }
}
