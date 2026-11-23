using Library.Example.Abstractions;

namespace Library.Example;

/// <summary>
/// Selects pages using the document's size from a catalog.
/// </summary>
public sealed class DocumentPageSelector
{
    private readonly IDocumentCatalog _catalog;

    /// <summary>
    /// Creates a selector for documents in the supplied catalog.
    /// </summary>
    /// <param name="catalog">The source of document page counts.</param>
    public DocumentPageSelector(IDocumentCatalog catalog)
    {
        ArgumentNullException.ThrowIfNull(catalog);
        _catalog = catalog;
    }

    /// <summary>
    /// Looks up the document and validates the selection against its page count.
    /// </summary>
    /// <param name="documentId">The document to look up in the catalog.</param>
    /// <param name="expression">Page numbers and inclusive ranges accepted by <see cref="PageRange.Parse"/>.</param>
    /// <param name="cancellationToken">Cancels the catalog request.</param>
    /// <returns>The selected pages, in ascending order, with duplicates removed.</returns>
    /// <exception cref="DocumentCatalogException">The catalog lookup failed.</exception>
    /// <exception cref="OperationCanceledException">The caller canceled the request.</exception>
    /// <exception cref="FormatException">The page selection is malformed.</exception>
    /// <exception cref="ArgumentOutOfRangeException">A selected page falls outside the document.</exception>
    public async Task<IEnumerable<int>> SelectAsync(string documentId, string expression, CancellationToken cancellationToken)
    {
        ValidateRequest(documentId, expression);
        var pageCount = await _catalog.GetPageCountAsync(documentId, cancellationToken).ConfigureAwait(false);
        return PageRange.Parse(expression, pageCount);
    }

    private static void ValidateRequest(string documentId, string expression)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(documentId);
        ArgumentNullException.ThrowIfNull(expression);
    }
}
