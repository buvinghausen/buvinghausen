_DIGITS = frozenset("0123456789")


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
            parts.append(f"{count}{prev}")
            prev = ch
            count = 1

    parts.append(f"{count}{prev}")
    return "".join(parts)


def rle_decode(s: str) -> str:
    if not s:
        return ""

    out = []
    i = 0
    n = len(s)

    while i < n:
        start = i
        while i < n and s[i] in _DIGITS:
            i += 1

        if i == start:
            raise ValueError("Expected a run count")

        count_str = s[start:i]

        if count_str[0] == "0":
            raise ValueError("Run count must be positive and have no leading zeros")

        if i >= n:
            raise ValueError("Expected a character after the run count")

        ch = s[i]
        out.append(ch * int(count_str))
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
