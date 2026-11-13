import re

_NUM = r"(?:[0-9]+(?:\.[0-9]+)?)"
_PATTERN = (
    r"P"
    rf"(?:(?P<years>{_NUM})Y)?"
    rf"(?:(?P<months>{_NUM})M)?"
    rf"(?:(?P<weeks>{_NUM})W)?"
    rf"(?:(?P<days>{_NUM})D)?"
    rf"(?:T(?={_NUM}(?:H|M|S))"
    rf"(?:(?P<hours>{_NUM})H)?"
    rf"(?:(?P<minutes>{_NUM})M)?"
    rf"(?:(?P<seconds>{_NUM})S)?"
    r")?"
)
_DURATION_RE = re.compile(_PATTERN, re.ASCII)

_SECONDS_PER_DAY = 24 * 60 * 60


def parse_duration(s: str) -> float:
    if not isinstance(s, str):
        raise ValueError("Invalid ISO-8601 duration")

    m = _DURATION_RE.fullmatch(s)
    if m is None:
        raise ValueError("Invalid ISO-8601 duration")

    group_names = ("years", "months", "weeks", "days", "hours", "minutes", "seconds")
    if all(m.group(name) is None for name in group_names):
        raise ValueError("Invalid ISO-8601 duration")

    total = 0.0
    factors = (
        ("years", 365 * _SECONDS_PER_DAY),
        ("months", 30 * _SECONDS_PER_DAY),
        ("weeks", 7 * _SECONDS_PER_DAY),
        ("days", _SECONDS_PER_DAY),
        ("hours", 60 * 60),
        ("minutes", 60),
        ("seconds", 1),
    )

    for name, factor in factors:
        value = m.group(name)
        if value is not None:
            total += float(value) * factor

    return total


# ---- tests ----
assert parse_duration('PT1H') == 3600
assert parse_duration('P1D') == 86400
assert parse_duration('P3W') == 3*7*86400
assert parse_duration('P1Y2M10DT2H30M15.5S') == 365*86400 + 60*86400 + 10*86400 + 2*3600 + 30*60 + 15.5
assert parse_duration('PT0.5H') == 1800
assert parse_duration('P1DT1S') == 86401
for bad in ['', 'P', 'PT', '1D', 'PT1D', 'P1H', 'PT1S1M', 'P1D2Y', 'Px']:
    try:
        parse_duration(bad)
    except ValueError:
        pass
    else:
        raise AssertionError('accepted ' + repr(bad))
