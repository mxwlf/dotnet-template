namespace Library.Example.Abstractions;

// A catalog failure always requires a classification. The conventional untyped constructors cannot supply one.
#pragma warning disable CA1032, RCS1194, S4027
/// <summary>
/// Describes a failure encountered while reading document metadata.
/// </summary>
public sealed class DocumentCatalogException : Exception
#pragma warning restore CA1032, RCS1194, S4027
{
    /// <summary>
    /// Creates a failure with its catalog classification.
    /// </summary>
    /// <param name="failure">The reason the lookup failed.</param>
    /// <param name="message">A description of the failure.</param>
    public DocumentCatalogException(DocumentCatalogFailure failure, string message)
        : this(failure, message, innerException: null)
    {
    }

    /// <summary>
    /// Creates a failure with its catalog classification and underlying cause.
    /// </summary>
    /// <param name="failure">The reason the lookup failed.</param>
    /// <param name="message">A description of the failure.</param>
    /// <param name="innerException">The underlying cause, when available.</param>
    public DocumentCatalogException(DocumentCatalogFailure failure, string message, Exception? innerException)
        : base(message, innerException)
    {
        Failure = failure;
    }

    /// <summary>
    /// Gets the reason the lookup failed.
    /// </summary>
    public DocumentCatalogFailure Failure { get; }

    /// <summary>
    /// Gets a value indicating whether a later lookup may succeed without changing the request.
    /// </summary>
    public bool IsTransient => Failure is DocumentCatalogFailure.Unavailable;
}
