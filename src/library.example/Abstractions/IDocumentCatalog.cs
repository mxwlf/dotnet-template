namespace Library.Example.Abstractions;

/// <summary>
/// Provides page counts for documents in a catalog.
/// </summary>
public interface IDocumentCatalog
{
    /// <summary>
    /// Reads the positive page count for the specified document.
    /// </summary>
    /// <param name="documentId">A catalog identifier made of ASCII letters, digits, hyphens, or underscores.</param>
    /// <param name="cancellationToken">Cancels the lookup.</param>
    /// <returns>The number of pages in the document.</returns>
    /// <exception cref="DocumentCatalogException">The catalog lookup failed.</exception>
    /// <exception cref="OperationCanceledException">The caller canceled the lookup.</exception>
    Task<int> GetPageCountAsync(string documentId, CancellationToken cancellationToken);
}
