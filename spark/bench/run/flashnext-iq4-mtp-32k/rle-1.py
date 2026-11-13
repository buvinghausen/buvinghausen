def rle_encode(s: str) -> str:
    if not s:
        return ""

    parts = []
    i = 0
    n = len(s)

    while i < n:
        j = i + 1
        while j < n and s[j] == s[i]:
            j += 1

        parts.append(str(j - i))
        parts.append(s[i])
        i = j

    return "".join(parts)


def rle_decode(s: str) -> str:
    if not s:
        return ""

    result = []
    i = 0
    n = len(s)

    def is_digit(ch: str) -> bool:
        return "0" <= ch <= "9"

    while i < n:
        if not is_digit(s[i]):
            raise ValueError("count must appear before each character")

        j = i
        while j < n and is_digit(s[j]):
            j += 1

        if j == n:
            raise ValueError("count must be followed by a character")

        count = int(s[i:j])
        if count == 0:
            raise ValueError("count must be positive")

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
