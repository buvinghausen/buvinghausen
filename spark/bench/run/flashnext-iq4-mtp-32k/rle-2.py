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


def _is_ascii_digit(ch: str) -> bool:
    return "0" <= ch <= "9"


def rle_decode(s: str) -> str:
    if not s:
        return ""

    parts = []
    n = len(s)
    i = 0

    while i < n:
        if not _is_ascii_digit(s[i]):
            raise ValueError("Malformed RLE string: expected count digits")

        j = i
        while j < n and _is_ascii_digit(s[j]):
            j += 1

        if j >= n:
            raise ValueError("Malformed RLE string: count is not followed by a character")

        if s[i] == "0":
            raise ValueError("Malformed RLE string: count must be positive")

        count = int(s[i:j])
        parts.append(s[j] * count)
        i = j + 1

    return "".join(parts)


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
