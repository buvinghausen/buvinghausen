from __future__ import annotations

def parse_csv_line(line: str) -> list[str]:
    fields = []
    i = 0
    n = len(line)

    while True:
        if i == n:
            fields.append("")
            break

        if line[i] == '"':
            i += 1
            chars = []

            while True:
                if i >= n:
                    raise ValueError("Unterminated quoted field")

                ch = line[i]
                if ch == '"':
                    if i + 1 < n and line[i + 1] == '"':
                        chars.append('"')
                        i += 2
                    else:
                        i += 1
                        break
                else:
                    chars.append(ch)
                    i += 1

            while i < n and line[i] != ',':
                chars.append(line[i])
                i += 1

            fields.append("".join(chars))
        else:
            start = i
            while i < n and line[i] != ',':
                i += 1
            fields.append(line[start:i])

        if i == n:
            break

        i += 1

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
