namespace Library.Example.Abstractions;

/// <summary>
/// Identifies why a document catalog lookup failed.
/// </summary>
public enum DocumentCatalogFailure
{
    /// <summary>
    /// The document could not be found.
    /// </summary>
    NotFound = 0,

    /// <summary>
    /// The catalog is temporarily unavailable.
    /// </summary>
    Unavailable = 1,

    /// <summary>
    /// The catalog supplied unusable document metadata.
    /// </summary>
    InvalidResponse = 2,

    /// <summary>
    /// The catalog refused the lookup.
    /// </summary>
    Rejected = 3,
}
