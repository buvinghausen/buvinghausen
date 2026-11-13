import re

_ROMAN_TABLE = (
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

_CANONICAL_RE = re.compile(
    r"\AM{0,3}(?:CM|CD|D?C{0,3})(?:XC|XL|L?X{0,3})(?:IX|IV|V?I{0,3})\Z"
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
    if isinstance(n, bool) or not isinstance(n, int):
        raise ValueError("n must be an integer between 1 and 3999")

    if not 1 <= n <= 3999:
        raise ValueError("n must be between 1 and 3999")

    parts = []
    remainder = n

    for value, symbol in _ROMAN_TABLE:
        count = remainder // value
        if count:
            parts.append(symbol * count)
            remainder -= value * count

    return "".join(parts)


def from_roman(s: str) -> int:
    if not isinstance(s, str) or not s:
        raise ValueError("s must be a non-empty canonical Roman numeral")

    if _CANONICAL_RE.match(s) is None:
        raise ValueError("s is not a canonical Roman numeral")

    total = 0
    previous = 0

    for ch in reversed(s):
        current = _ROMAN_VALUES[ch]
        if current < previous:
            total -= current
        else:
            total += current
            previous = current

    if not 1 <= total <= 3999:
        raise ValueError("Roman numeral value must be between 1 and 3999")

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
