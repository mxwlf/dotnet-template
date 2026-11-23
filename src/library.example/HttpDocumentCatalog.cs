using System.Net;
using System.Text.Json;

using Library.Example.Abstractions;

using Microsoft.Extensions.Http.Resilience;

using Polly;

namespace Library.Example;

internal sealed class HttpDocumentCatalog(HttpClient client) : IDocumentCatalog
{
    public async Task<int> GetPageCountAsync(string documentId, CancellationToken cancellationToken)
    {
        var path = GetDocumentPath(documentId);
        try
        {
            using var response = await client.GetAsync(path, cancellationToken).ConfigureAwait(false);
            cancellationToken.ThrowIfCancellationRequested();
            EnsureSuccess(response);
            var json = await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false);
            return ReadPageCount(json);
        }
        catch (JsonException ex)
        {
            throw new DocumentCatalogException(DocumentCatalogFailure.InvalidResponse, "The catalog returned invalid JSON.", ex);
        }
        catch (HttpRequestException ex)
        {
            var failure = ClassifyTransportError(ex);
            throw new DocumentCatalogException(failure, "The catalog request failed.", ex);
        }
        catch (ExecutionRejectedException ex)
        {
            throw new DocumentCatalogException(DocumentCatalogFailure.Unavailable, "The catalog is temporarily unavailable.", ex);
        }
        catch (OperationCanceledException ex) when (!cancellationToken.IsCancellationRequested)
        {
            throw new DocumentCatalogException(DocumentCatalogFailure.Unavailable, "The catalog request timed out.", ex);
        }
    }

    internal static DocumentCatalogFailure ClassifyTransportError(HttpRequestException exception)
    {
        var error = exception.HttpRequestError;
        if (error is HttpRequestError.NameResolutionError or HttpRequestError.ConnectionError or HttpRequestError.ResponseEnded)
        {
            return DocumentCatalogFailure.Unavailable;
        }

        return error is HttpRequestError.InvalidResponse or HttpRequestError.ConfigurationLimitExceeded
            ? DocumentCatalogFailure.InvalidResponse
            : DocumentCatalogFailure.Rejected;
    }

    private static Uri GetDocumentPath(string documentId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(documentId);
        if (!documentId.All(static c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_'))
        {
            throw new ArgumentException("Use letters, digits, hyphens, or underscores for the document ID.", nameof(documentId));
        }

        return new Uri(documentId + ".json", UriKind.Relative);
    }

    private static void EnsureSuccess(HttpResponseMessage response)
    {
        if (response.IsSuccessStatusCode)
        {
            return;
        }

        if (response.StatusCode is HttpStatusCode.NotFound)
        {
            throw new DocumentCatalogException(DocumentCatalogFailure.NotFound, "The document was not found.");
        }

        var outcome = Outcome.FromResult(response);
        var failure = HttpClientResiliencePredicates.IsTransient(outcome) ? DocumentCatalogFailure.Unavailable : DocumentCatalogFailure.Rejected;
        throw new DocumentCatalogException(failure, $"The catalog returned HTTP {response.StatusCode:D}.");
    }

    private static int ReadPageCount(byte[] json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var count = root.ValueKind is JsonValueKind.Object && root.TryGetProperty("pageCount", out var property) ? property : default;
        if (count.ValueKind is JsonValueKind.Number && count.TryGetInt32(out var pageCount) && pageCount > 0)
        {
            return pageCount;
        }

        throw new DocumentCatalogException(DocumentCatalogFailure.InvalidResponse, "Catalog metadata must contain a positive integer pageCount.");
    }
}
