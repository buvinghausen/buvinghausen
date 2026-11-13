import re

_CANONICAL_ROMAN_RE = re.compile(
    r"M{0,3}(?:CM|CD|D?C{0,3})(?:XC|XL|L?X{0,3})(?:IX|IV|V?I{0,3})"
)

_TO_ROMAN_RULES = (
    (1000, "M"),
    (900, "CM"),
    (500, "D"),
    (400, "CD"),
    (100, "C"),
    (90, "XC"),
    (50, "L"),
    (40, "XL"),
    (10, "X"),
    (9, "IX"),
    (5, "V"),
    (4, "IV"),
    (1, "I"),
)

_ROMAN_VALUES = {
    "I": 1,
    "V": 5,
    "X": 10,
    "L": 50,
    "C": 100,
    "D": 500,
    "M": 1000,
}


def to_roman(n: int) -> str:
    if not isinstance(n, int) or isinstance(n, bool) or not 1 <= n <= 3999:
        raise ValueError("n must be an integer between 1 and 3999")

    parts = []
    for value, numeral in _TO_ROMAN_RULES:
        while n >= value:
            parts.append(numeral)
            n -= value

    return "".join(parts)


def from_roman(s: str) -> int:
    if not isinstance(s, str) or not s:
        raise ValueError("s must be a non-empty string")

    if not _CANONICAL_ROMAN_RE.fullmatch(s):
        raise ValueError("s must be a canonical Roman numeral")

    total = 0
    for i, ch in enumerate(s):
        value = _ROMAN_VALUES[ch]
        if i + 1 < len(s) and value < _ROMAN_VALUES[s[i + 1]]:
            total -= value
        else:
            total += value

    if to_roman(total) != s:
        raise ValueError("s must be a canonical Roman numeral")

    return total


# ---- tests ----
for n,s in [(1,'I'),(4,'IV'),(9,'IX'),(14,'XIV'),(40,'XL'),(90,'XC'),(400,'CD'),(944,'CMXLIV'),(1994,'MCMXCIV'),(3999,'MMMCMXCIX')]:
    assert to_roman(n) == s, (n, to_roman(n))
    assert from_roman(s) == n
for n in range(1, 4000):
    assert from_roman(to_roman(n)) == n
for bad in [0, 4000, -1]:
    try:
        to_roman(bad)
    except ValueError:
        pass
    else:
        raise AssertionError(bad)
for bad in ['IIII', 'IC', 'VX', '', 'iv', 'MMMM', 'XXC', 'IL']:
    try:
        from_roman(bad)
    except ValueError:
        pass
    else:
        raise AssertionError(bad)
