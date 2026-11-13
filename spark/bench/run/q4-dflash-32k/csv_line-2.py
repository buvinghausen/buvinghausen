def parse_csv_line(line: str) -> list[str]:
    """Parse a single CSV line according to RFC 4180 quoting rules."""
    if line == "":
        return []

    fields: list[str] = []
    field: list[str] = []
    in_quotes = False
    i = 0
    n = len(line)

    while i < n:
        ch = line[i]

        if in_quotes:
            if ch == '"':
                if i + 1 < n and line[i + 1] == '"':
                    field.append('"')
                    i += 2
                    continue
                in_quotes = False
            else:
                field.append(ch)
        else:
            if ch == ",":
                fields.append("".join(field))
                field = []
            elif ch == '"':
                if not field:
                    in_quotes = True
                else:
                    field.append(ch)
            else:
                field.append(ch)

        i += 1

    if in_quotes:
        raise ValueError("Unterminated quoted field")

    fields.append("".join(field))
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
