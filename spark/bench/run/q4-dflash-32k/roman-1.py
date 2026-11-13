_ROMAN_VALUES = (
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

_DIGIT_VALUES = {
    "I": 1,
    "V": 5,
    "X": 10,
    "L": 50,
    "C": 100,
    "D": 500,
    "M": 1000,
}


def to_roman(n: int) -> str:
    if not isinstance(n, int) or not 1 <= n <= 3999:
        raise ValueError("n must be an integer between 1 and 3999")

    parts = []
    for value, symbol in _ROMAN_VALUES:
        count, n = divmod(n, value)
        if count:
            parts.append(symbol * count)
    return "".join(parts)


def from_roman(s: str) -> int:
    if not isinstance(s, str):
        raise ValueError("input must be a string")
    if not s:
        raise ValueError("Roman numeral cannot be empty")
    if len(s) > 15:
        raise ValueError("invalid Roman numeral")

    total = 0
    previous = 0

    for ch in reversed(s):
        value = _DIGIT_VALUES.get(ch)
        if value is None:
            raise ValueError("invalid Roman numeral character")

        if value < previous:
            total -= value
        else:
            total += value

        previous = value

    try:
        canonical = to_roman(total)
    except ValueError:
        raise ValueError("invalid Roman numeral") from None

    if canonical != s:
        raise ValueError("invalid Roman numeral")

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
