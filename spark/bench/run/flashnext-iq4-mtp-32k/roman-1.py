import re

_INT_TO_ROMAN = (
    (1000, "M"),
    (900, "CM"),
    (500, "D"),
    (100, "C"),
    (90, "XC"),
    (50, "L"),
    (10, "X"),
    (9, "IX"),
    (5, "V"),
    (4, "IV"),
    (1, "I"),
)

_ROMAN_TO_INT = {
    "I": 1,
    "V": 5,
    "X": 10,
    "L": 50,
    "C": 100,
    "D": 500,
    "M": 1000,
}

_CANONICAL_ROMAN = re.compile(
    r"M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})"
)


def to_roman(n: int) -> str:
    if isinstance(n, bool) or not isinstance(n, int):
        raise ValueError("n must be an integer")
    if not (1 <= n <= 3999):
        raise ValueError("n must be between 1 and 3999 inclusive")

    parts = []
    for value, numeral in _INT_TO_ROMAN:
        count, n = divmod(n, value)
        if count:
            parts.append(numeral * count)

    return "".join(parts)


def from_roman(s: str) -> int:
    if not isinstance(s, str) or not s:
        raise ValueError("s must be a canonical Roman numeral")
    if not _CANONICAL_ROMAN.fullmatch(s):
        raise ValueError("s must be a canonical Roman numeral")

    total = 0
    previous_value = 0

    for char in reversed(s):
        value = _ROMAN_TO_INT[char]
        if value < previous_value:
            total -= value
        else:
            total += value
            previous_value = value

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
