from __future__ import annotations

def parse_csv_line(line: str) -> list[str]:
    fields = []
    i = 0
    n = len(line)

    while True:
        if i >= n:
            fields.append("")
            return fields

        if line[i] == '"':
            i += 1
            parts = []
            closed = False

            while i < n:
                ch = line[i]
                if ch == '"':
                    if i + 1 < n and line[i + 1] == '"':
                        parts.append('"')
                        i += 2
                    else:
                        i += 1
                        closed = True
                        break
                else:
                    parts.append(ch)
                    i += 1

            if not closed:
                raise ValueError("Unterminated quoted field")

            if i < n and line[i] != ',':
                while i < n and line[i] != ',':
                    parts.append(line[i])
                    i += 1

            fields.append("".join(parts))

            if i >= n:
                return fields

            i += 1
        else:
            j = i
            while j < n and line[j] != ',':
                j += 1

            fields.append(line[i:j])

            if j >= n:
                return fields

            i = j + 1


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
