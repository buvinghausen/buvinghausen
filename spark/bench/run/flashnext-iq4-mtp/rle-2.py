def rle_encode(s: str) -> str:
    if not s:
        return ""

    parts = []
    i = 0
    n = len(s)

    while i < n:
        ch = s[i]
        j = i + 1

        while j < n and s[j] == ch:
            j += 1

        parts.append(str(j - i))
        parts.append(ch)
        i = j

    return "".join(parts)


def rle_decode(s: str) -> str:
    if not s:
        return ""

    def is_digit(c: str) -> bool:
        return "0" <= c <= "9"

    parts = []
    i = 0
    n = len(s)

    while i < n:
        start = i

        while i < n and is_digit(s[i]):
            i += 1

        if start == i:
            raise ValueError("Malformed run-length encoded string: expected count")

        count_digits = s[start:i]

        if count_digits[0] == "0":
            raise ValueError("Malformed run-length encoded string: count must be positive")

        count = int(count_digits)

        if i >= n:
            raise ValueError("Malformed run-length encoded string: expected character after count")

        parts.append(s[i] * count)
        i += 1

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
