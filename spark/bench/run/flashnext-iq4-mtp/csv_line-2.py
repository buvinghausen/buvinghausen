from __future__ import annotations


def parse_csv_line(line: str) -> list[str]:
    """
    Parse a single CSV line using RFC 4180-style quoting.

    - Fields are split on commas.
    - A field may be enclosed in double quotes.
    - Inside a quoted field, a doubled double-quote represents a literal quote.
    - Unquoted fields are returned as-is, with no stripping.
    - Raises ValueError for an unterminated quoted field.
    """
    fields: list[str] = []
    current: list[str] = []

    in_quotes = False
    field_start = True

    i = 0
    n = len(line)

    while i < n:
        ch = line[i]

        if in_quotes:
            if ch == '"':
                if i + 1 < n and line[i + 1] == '"':
                    current.append('"')
                    i += 2
                else:
                    in_quotes = False
                    i += 1
            else:
                current.append(ch)
                i += 1
        else:
            if ch == '"' and field_start:
                in_quotes = True
                field_start = False
                i += 1
            elif ch == ',':
                fields.append(''.join(current))
                current = []
                field_start = True
                i += 1
            else:
                current.append(ch)
                field_start = False
                i += 1

    if in_quotes:
        raise ValueError("Unterminated quoted field")

    fields.append(''.join(current))
    return fields


# ---- tests ----
assert parse_csv_line('a,b,c') == ['a','b','c']
assert parse_csv_line('') == ['']
assert parse_csv_line('a,,c') == ['a','','c']
assert parse_csv_line('"a,b",c') == ['a,b','c']
assert parse_csv_line('"he said ""hi""",x') == ['he said "hi"','x']
assert parse_csv_line(' a , b ') == [' a ',' b ']
assert parse_csv_line('a,') == ['a','']
assert parse_csv_line('""') == ['']
try:
    parse_csv_line('"abc,d')
except ValueError:
    pass
else:
    raise AssertionError('unterminated accepted')
