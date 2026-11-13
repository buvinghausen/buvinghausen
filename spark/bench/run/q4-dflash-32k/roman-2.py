import operator
import re

def to_roman(n: int) -> str:
    try:
        n = operator.index(n)
    except TypeError:
        raise ValueError("n must be an integer between 1 and 3999") from None

    if not 1 <= n <= 3999:
        raise ValueError("n must be an integer between 1 and 3999")

    numerals = [
        (1000, "M"),
        (900, "CM"),
        (500, "CD"),
        (100, "C"),
        (90, "XC"),
        (50, "XL"),
        (10, "X"),
        (9, "IX"),
        (5, "V"),
        (4, "IV"),
        (1, "I"),
    ]

    result = []
    for value, symbol in numerals:
        while n >= value:
            result.append(symbol)
            n -= value

    return "".join(result)


_ROMAN_RE = re.compile(
    r"M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})"
)
_ROMAN_VALUES = {
    "M": 1000,
    "D": 500,
    "C": 100,
    "L": 50,
    "X": 10,
    "V": 5,
    "I": 1,
}


def from_roman(s: str) -> int:
    if not isinstance(s, str) or not 1 <= len(s) <= 15:
        raise ValueError("s must be a canonical Roman numeral")

    if not _ROMAN_RE.fullmatch(s):
        raise ValueError("s must be a canonical Roman numeral")

    total = 0
    values = _ROMAN_VALUES

    for i, ch in enumerate(s):
        value = values[ch]
        if i + 1 < len(s) and values[s[i + 1]] > value:
            total -= value
        else:
            total += value

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
