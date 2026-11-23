using System.Net;
using System.Net.Http.Headers;
using System.Text;

using Microsoft.Extensions.DependencyInjection;

namespace Library.Example.Tests.Unit;

internal sealed class ScriptedHandler(Func<int, HttpResponseMessage> respond) : HttpMessageHandler
{
    internal static readonly Uri ScenarioDirectory = new("https://catalog.example/scenarios/eight-pages/");

    internal int Attempts { get; private set; }

    internal Uri? RequestUri { get; private set; }

    internal HttpMethod? Method { get; private set; }

    internal ServiceProvider Compose()
    {
        var services = new ServiceCollection();
        services.AddDocumentPageSelection(ScenarioDirectory).ConfigurePrimaryHttpMessageHandler(() => this);
        return services.BuildServiceProvider();
    }

    internal static HttpResponseMessage JsonResponse(string json)
    {
        return new(HttpStatusCode.OK)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json"),
        };
    }

    internal static HttpResponseMessage RetryableResponse(HttpStatusCode statusCode, TimeSpan? retryAfter = null)
    {
        return new(statusCode)
        {
            Headers = { RetryAfter = new RetryConditionHeaderValue(retryAfter ?? TimeSpan.Zero) },
        };
    }

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        RequestUri = request.RequestUri;
        Method = request.Method;
        Attempts++;
        return Task.FromResult(respond(Attempts));
    }
}
