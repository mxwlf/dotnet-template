using System.Globalization;

namespace Library.Example;

/// <summary>
/// Parses a print-style selection of document pages.
/// </summary>
#pragma warning disable MA0104 // The print-range API shares a name with a WPF type in a platform-specific assembly.
public static class PageRange
{
#pragma warning restore MA0104
    /// <summary>
    /// Checks the complete selection and returns its pages in ascending order.
    /// </summary>
    /// <param name="expression">Comma-separated page numbers or inclusive ranges, such as <c>1, 3-5, 4</c>. Whitespace around numbers is allowed.</param>
    /// <param name="pageCount">The positive number of pages in the document. Page numbering starts at one.</param>
    /// <returns>A sequence that expands the validated ranges on demand and yields each page once.</returns>
    /// <exception cref="ArgumentNullException"><paramref name="expression"/> is null.</exception>
    /// <exception cref="ArgumentOutOfRangeException">The page count is less than one or a selected page falls outside the document.</exception>
    /// <exception cref="FormatException">A term is missing, contains an invalid number, or has its endpoints reversed.</exception>
    public static IEnumerable<int> Parse(string expression, int pageCount)
    {
        ArgumentNullException.ThrowIfNull(expression);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(pageCount);

        var ranges = new List<(int First, int Last)>();
        foreach (var term in expression.Split(','))
        {
            var range = ParseTerm(term);
            if (range.First < 1 || range.Last > pageCount)
            {
                throw new ArgumentOutOfRangeException(nameof(expression), term, "A selected page falls outside the document.");
            }

            ranges.Add(range);
        }

        ranges.Sort();
        return Expand(ranges);
    }

    private static (int First, int Last) ParseTerm(ReadOnlySpan<char> term)
    {
        var dash = term.IndexOf('-');
        if (dash < 0)
        {
            var page = ReadPage(term);
            return (page, page);
        }

        var first = ReadPage(term[..dash]);
        var last = ReadPage(term[(dash + 1)..]);
        if (first > last)
        {
            throw new FormatException("A range must start at or before its last page.");
        }

        return (first, last);
    }

    private static int ReadPage(ReadOnlySpan<char> text)
    {
        var digits = text.Trim();
        if (digits.ContainsAnyExceptInRange('0', '9') || !int.TryParse(digits, NumberStyles.None, CultureInfo.InvariantCulture, out var page))
        {
            throw new FormatException("Expected a page number made of decimal digits within the Int32 range.");
        }

        return page;
    }

    private static IEnumerable<int> Expand(List<(int First, int Last)> ranges)
    {
        var previousEnd = 0;
        foreach (var (first, last) in ranges)
        {
            if (last <= previousEnd)
            {
                continue;
            }

            var start = Math.Max(first, previousEnd + 1);
            foreach (var page in Enumerable.Range(start, last - start + 1))
            {
                yield return page;
            }

            previousEnd = last;
        }
    }
}
