# Page selection

Select pages from a document by number or inclusive range. The parser returns
each page once, in ascending order. It validates the selection against the
document's page count.

```csharp
using Library.Example;

var pages = PageRange.Parse("8, 3-5, 4", pageCount: 8);
// 3, 4, 5, 8
```

## Use a remote document catalog

Register a catalog directory as the HTTP client's base address. Give each
document a JSON file containing its page count, for example
`handbook.json` containing `{ "pageCount": 8 }`. The selector looks up the
count when the caller supplies a document ID.

```csharp
using Library.Example;
using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection();
services.AddDocumentPageSelection(new Uri("https://catalog.example.org/documents/"));
using var provider = services.BuildServiceProvider();
var selector = provider.GetRequiredService<DocumentPageSelector>();

var pages = await selector.SelectAsync("handbook", "3-5, 8", cancellationToken);
// GET /documents/handbook.json → 3, 4, 5, 8
```

The catalog uses a read-only GET and makes up to three attempts in total for
transient failures such as HTTP 429 or 503. The client applies a 30-second
overall timeout. Caller cancellation propagates as `OperationCanceledException`.

| Outcome | What the caller receives |
| --- | --- |
| Unknown document (HTTP 404) | `DocumentCatalogException` with `Failure == NotFound` |
| Catalog still unavailable after retries | `Failure == Unavailable` and `IsTransient == true` |
| Invalid JSON or an invalid or missing page count | `Failure == InvalidResponse` |
| A rejected request, such as HTTP 403 | `Failure == Rejected` |
| An invalid range expression | `FormatException` for malformed or reversed ranges, or `ArgumentOutOfRangeException` for a page outside the document |

## Test with a substitute

A test can supply a known document length through the catalog interface and
exercise the real selector and parser.

```csharp
using Library.Example;
using Library.Example.Abstractions;
using NSubstitute;

var catalog = Substitute.For<IDocumentCatalog>();
catalog.GetPageCountAsync("handbook", cancellationToken).Returns(8);
var selector = new DocumentPageSelector(catalog);

var pages = await selector.SelectAsync("handbook", "8", cancellationToken);
// 8
```

## License

MIT.
