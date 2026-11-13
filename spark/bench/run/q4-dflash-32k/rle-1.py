def rle_encode(s: str) -> str:
    if not s:
        return ""

    parts = []
    current = s[0]
    count = 1

    for ch in s[1:]:
        if ch == current:
            count += 1
        else:
            parts.append(f"{count}{current}")
            current = ch
            count = 1

    parts.append(f"{count}{current}")
    return "".join(parts)


def rle_decode(s: str) -> str:
    if not s:
        return ""

    out = []
    i = 0
    n = len(s)

    while i < n:
        start = i
        while i < n and "0" <= s[i] <= "9":
            i += 1

        if i == start:
            raise ValueError("malformed RLE: expected a count")
        if i >= n:
            raise ValueError("malformed RLE: missing character")
        if s[start] == "0":
            raise ValueError("malformed RLE: count must be positive with no leading zeros")

        count = int(s[start:i])
        out.append(s[i] * count)
        i += 1

    return "".join(out)


# ---- tests ----
assert rle_encode('') == ''
assert rle_decode('') == ''
assert rle_encode('aaabcc') == '3a1b2c'
assert rle_encode('a'*12 + 'b') == '12a1b'
assert rle_decode('12a1b') == 'a'*12 + 'b'
for s in ['x', 'xyz', 'aabbaa', ' ' * 5 + '!']:
    assert rle_decode(rle_encode(s)) == s
for bad in ['a', '3', '0a', '2a3']:
    try:
        rle_decode(bad)
    except ValueError:
        pass
    else:
        raise AssertionError(bad)
