using Library.Example.Abstractions;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Http.Resilience;

using Polly;

namespace Library.Example;

/// <summary>
/// Registers page selection backed by a remote JSON catalog.
/// </summary>
public static class DocumentPageSelectionExtensions
{
    private const int MaximumRetries = 2;
    private const int MaximumMetadataBytes = 64 * 1024;

    /// <summary>
    /// Registers the selector and a resilient HTTP client for document metadata.
    /// </summary>
    /// <param name="services">The services to configure.</param>
    /// <param name="baseAddress">An absolute HTTP or HTTPS directory URL ending in a slash.</param>
    /// <returns>The HTTP client builder for further configuration.</returns>
    /// <exception cref="ArgumentException"><paramref name="baseAddress"/> is not an HTTP or HTTPS directory URL.</exception>
    public static IHttpClientBuilder AddDocumentPageSelection(this IServiceCollection services, Uri baseAddress)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(baseAddress);
        var isHttpAddress = baseAddress.IsAbsoluteUri &&
            (string.Equals(baseAddress.Scheme, Uri.UriSchemeHttp, StringComparison.Ordinal) ||
             string.Equals(baseAddress.Scheme, Uri.UriSchemeHttps, StringComparison.Ordinal));
        if (!isHttpAddress || !baseAddress.AbsolutePath.EndsWith('/') || baseAddress.Query.Length > 0 || baseAddress.Fragment.Length > 0)
        {
            throw new ArgumentException("Supply an absolute HTTP or HTTPS directory URL ending in a slash, without a query or fragment.", nameof(baseAddress));
        }

        services.AddTransient<DocumentPageSelector>();
        var builder = services.AddHttpClient<IDocumentCatalog, HttpDocumentCatalog>(client => client.BaseAddress = baseAddress);
        builder.AddStandardResilienceHandler(static options =>
        {
            options.Retry.MaxRetryAttempts = MaximumRetries;
            options.Retry.ShouldHandle = static args => ValueTask.FromResult(!args.Context.CancellationToken.IsCancellationRequested && IsTransient(args.Outcome));
            options.CircuitBreaker.ShouldHandle = static args => ValueTask.FromResult(!args.Context.CancellationToken.IsCancellationRequested && IsTransient(args.Outcome));
        });

        // Cover reading the response body as well as the time spent inside the HTTP handler.
        builder.ConfigureHttpClient(static client =>
        {
            client.Timeout = TimeSpan.FromSeconds(30);
            client.MaxResponseContentBufferSize = MaximumMetadataBytes;
        });
        return builder;
    }

    private static bool IsTransient(in Outcome<HttpResponseMessage> outcome)
    {
        return outcome.Exception is HttpRequestException ex
            ? HttpDocumentCatalog.ClassifyTransportError(ex) is DocumentCatalogFailure.Unavailable
            : HttpClientResiliencePredicates.IsTransient(outcome);
    }
}
