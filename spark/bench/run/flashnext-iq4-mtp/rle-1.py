def rle_encode(s: str) -> str:
    if not s:
        return ""

    parts = []
    prev = s[0]
    count = 1

    for ch in s[1:]:
        if ch == prev:
            count += 1
        else:
            parts.append(str(count))
            parts.append(prev)
            prev = ch
            count = 1

    parts.append(str(count))
    parts.append(prev)
    return "".join(parts)


def _is_ascii_digit(ch: str) -> bool:
    return "0" <= ch <= "9"


def rle_decode(s: str) -> str:
    if not s:
        return ""

    result = []
    i = 0
    n = len(s)

    while i < n:
        if not _is_ascii_digit(s[i]):
            raise ValueError("malformed RLE string: expected a count")

        j = i
        while j < n and _is_ascii_digit(s[j]):
            j += 1

        if j >= n:
            raise ValueError("malformed RLE string: count missing a character")

        count_str = s[i:j]

        if count_str[0] == "0":
            raise ValueError("malformed RLE string: invalid count")

        count = int(count_str)
        result.append(s[j] * count)
        i = j + 1

    return "".join(result)


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
