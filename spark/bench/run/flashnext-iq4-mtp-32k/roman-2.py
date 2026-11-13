_ROMAN_MAP = (
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


def to_roman(n: int) -> str:
    """Convert an integer from 1 to 3999 to a canonical Roman numeral."""
    if not isinstance(n, int):
        raise ValueError("n must be an integer")
    if n < 1 or n > 3999:
        raise ValueError("n must be between 1 and 3999 inclusive")

    result = []
    for value, symbol in _ROMAN_MAP:
        while n >= value:
            result.append(symbol)
            n -= value

    return "".join(result)


def from_roman(s: str) -> int:
    """Convert a canonical Roman numeral to an integer."""
    if not isinstance(s, str):
        raise ValueError("s must be a string")
    if not s:
        raise ValueError("s must not be empty")

    total = 0
    pos = 0
    length = len(s)

    for value, symbol in _ROMAN_MAP:
        while pos < length and s.startswith(symbol, pos):
            total += value
            if total > 3999:
                raise ValueError("s must represent a Roman numeral between 1 and 3999")
            pos += len(symbol)

    if pos != length:
        raise ValueError("s must contain only valid canonical Roman numeral symbols")
    if total < 1:
        raise ValueError("s must represent a positive Roman numeral")
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
