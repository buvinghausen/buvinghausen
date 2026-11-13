            if closed:
                if i < n and line[i] != ',':
                    # append remainder of this physical field until comma
                    while i < n and line[i] != ',':
                        chars.append(line[i])
                        i += 1
                if i == n: fields.append(''.join(chars)); break
                if line[i] == ',': fields.append(...); i +=1


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
