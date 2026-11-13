from __future__ import annotations

def parse_csv_line(line: str) -> list[str]:
    """
    Split one CSV line on commas using RFC 4180 double-quote semantics.

    - Fields may be wrapped in double quotes.
    - Commas inside quoted fields are literal.
    - "" inside a quoted field represents a single double quote.
    - Unquoted fields are returned as-is.
    - Raises ValueError for an unterminated quoted field.
    """
    fields: list[str] = []
    field: list[str] = []

    in_quotes = False
    at_field_start = True
    i = 0
    n = len(line)

    while i < n:
        ch = line[i]

        if in_quotes:
            if ch == '"':
                # A doubled quote inside a quoted field is an escaped quote.
                if i + 1 < n and line[i + 1] == '"':
                    field.append('"')
                    i += 2
                else:
                    # Closing quote.
                    in_quotes = False
                    i += 1
            else:
                field.append(ch)
                i += 1
        else:
            if ch == ',':
                fields.append(''.join(field))
                field = []
                at_field_start = True
                i += 1
            elif ch == '"' and at_field_start:
                # Begin a quoted field.
                in_quotes = True
                at_field_start = False
                i += 1
            else:
                field.append(ch)
                at_field_start = False
                i += 1

    if in_quotes:
        raise ValueError("Unterminated quoted field")

    fields.append(''.join(field))
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
