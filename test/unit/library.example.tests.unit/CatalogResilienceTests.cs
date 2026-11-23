using System.Net;

using AwesomeAssertions;

using Library.Example.Abstractions;

using Microsoft.Extensions.DependencyInjection;

namespace Library.Example.Tests.Unit;

/// <summary>
/// Tests the resilience policy composed with the document catalog.
/// </summary>
public class CatalogResilienceTests
{
    [Theory]
    [InlineData(HttpStatusCode.ServiceUnavailable)]
    [InlineData(HttpStatusCode.TooManyRequests)]
    public async Task GetPageCountAsync_WhenTheCatalogRecovers_ThenReturnsThePageCountOnRetry(HttpStatusCode transientStatus)
    {
        // Arrange
        using var transport = new ScriptedHandler(attempt => attempt is 1 ? ScriptedHandler.RetryableResponse(transientStatus) : ScriptedHandler.JsonResponse("""{"pageCount":8}"""));
        await using var services = transport.Compose();
        var catalog = services.GetRequiredService<IDocumentCatalog>();

        // Act
        var count = await catalog.GetPageCountAsync("manual", TestContext.Current.CancellationToken);

        // Assert
        count.Should().Be(8, "the second attempt returned valid metadata");
        transport.Attempts.Should().Be(2, "recovery ends the retry sequence");
    }

    [Fact]
    public async Task GetPageCountAsync_WhenTheCatalogRemainsUnavailable_ThenStopsAfterTwoRetries()
    {
        // Arrange
        using var transport = new ScriptedHandler(static _ => ScriptedHandler.RetryableResponse(HttpStatusCode.ServiceUnavailable));
        await using var services = transport.Compose();
        var catalog = services.GetRequiredService<IDocumentCatalog>();

        // Act
        var lookup = async () => await catalog.GetPageCountAsync("manual", TestContext.Current.CancellationToken);

        // Assert
        var error = await lookup.Should().ThrowAsync<DocumentCatalogException>("the retry budget was exhausted");
        error.Which.Failure.Should().Be(DocumentCatalogFailure.Unavailable, "the catalog remained unavailable across all attempts");
        error.Which.IsTransient.Should().BeTrue("a later lookup could succeed without changing the request");
        transport.Attempts.Should().Be(3, "two retries are permitted after the initial request");
    }

    [Theory]
    [InlineData(HttpRequestError.ConnectionError, DocumentCatalogFailure.Unavailable, 3)]
    [InlineData(HttpRequestError.SecureConnectionError, DocumentCatalogFailure.Rejected, 1)]
    public async Task GetPageCountAsync_WhenTheTransportFails_ThenRetriesOnlyRecoverableFailures(
        HttpRequestError transportError, DocumentCatalogFailure expectedFailure, int expectedAttempts)
    {
        // Arrange
        using var transport = new ScriptedHandler(_ => throw new HttpRequestException(transportError));
        await using var services = transport.Compose();
        var catalog = services.GetRequiredService<IDocumentCatalog>();

        // Act
        var lookup = async () => await catalog.GetPageCountAsync("manual", TestContext.Current.CancellationToken);

        // Assert
        var error = await lookup.Should().ThrowAsync<DocumentCatalogException>("the catalog translates transport failures for its caller");
        error.Which.Failure.Should().Be(expectedFailure, "connection loss and TLS negotiation failures require different handling");
        transport.Attempts.Should().Be(expectedAttempts, "only recoverable transport failures should consume the retry budget");
    }

    [Fact]
    public async Task GetPageCountAsync_WhenTheCallerCancelsAfterTheFirstRequest_ThenPropagatesCancellation()
    {
        // Arrange
        using var cancellation = CancellationTokenSource.CreateLinkedTokenSource(TestContext.Current.CancellationToken);
        using var transport = new ScriptedHandler(_ =>
        {
            cancellation.CancelAfter(TimeSpan.Zero);
            return ScriptedHandler.RetryableResponse(HttpStatusCode.ServiceUnavailable, TimeSpan.FromMinutes(1));
        });
        await using var services = transport.Compose();
        var catalog = services.GetRequiredService<IDocumentCatalog>();

        // Act
        var lookup = async () => await catalog.GetPageCountAsync("manual", cancellation.Token);

        // Assert
        await lookup.Should().ThrowAsync<OperationCanceledException>("the caller withdrew the request");
        transport.Attempts.Should().Be(1, "cancellation stops retries even when the server signals a temporary failure");
    }
}
