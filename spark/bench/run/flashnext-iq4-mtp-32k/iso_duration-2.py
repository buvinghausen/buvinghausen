import re
from decimal import Decimal

_NUM = r"[0-9]+(?:\.[0-9]+)?"

_DATE_RE = re.compile(
    rf"(?:(?P<years>{_NUM})Y)?"
    rf"(?:(?P<months>{_NUM})M)?"
    rf"(?:(?P<weeks>{_NUM})W)?"
    rf"(?:(?P<days>{_NUM})D)?"
)

_TIME_RE = re.compile(
    rf"(?:(?P<hours>{_NUM})H)?"
    rf"(?:(?P<minutes>{_NUM})M)?"
    rf"(?:(?P<seconds>{_NUM})S)?"
)

_DATE_NAMES = ("years", "months", "weeks", "days")
_TIME_NAMES = ("hours", "minutes", "seconds")

_SECONDS_PER_YEAR = Decimal(365 * 86400)
_SECONDS_PER_MONTH = Decimal(30 * 86400)
_SECONDS_PER_WEEK = Decimal(7 * 86400)
_SECONDS_PER_DAY = Decimal(86400)
_SECONDS_PER_HOUR = Decimal(3600)
_SECONDS_PER_MINUTE = Decimal(60)


def _decimal_value(match, name):
    if match is None:
        return Decimal(0)
    value = match.group(name)
    if value is None:
        return Decimal(0)
    return Decimal(value)


def _has_component(match, names):
    if match is None:
        return False
    return any(match.group(name) is not None for name in names)


def parse_duration(s: str) -> float:
    if not isinstance(s, str):
        raise ValueError("duration must be a string")
    if not s:
        raise ValueError("empty duration")

    sign = 1
    if s[0] == "-":
        sign = -1
        s = s[1:]

    if not s.startswith("P"):
        raise ValueError("duration must start with 'P'")

    s = s[1:]

    if not s:
        raise ValueError("duration must contain at least one component")

    if "T" in s:
        date_part, time_part = s.split("T", 1)
        if "T" in time_part:
            raise ValueError("invalid T position")
        if not time_part:
            raise ValueError("empty time part")
    else:
        date_part, time_part = s, None

    if date_part == "" and time_part is None:
        raise ValueError("duration must contain at least one component")

    date_match = _DATE_RE.fullmatch(date_part) if date_part else None
    if date_part and date_match is None:
        raise ValueError("invalid date component or order")

    time_match = _TIME_RE.fullmatch(time_part) if time_part is not None else None
    if time_part is not None and time_match is None:
        raise ValueError("invalid time component or order")

    if not (
        _has_component(date_match, _DATE_NAMES)
        or _has_component(time_match, _TIME_NAMES)
    ):
        raise ValueError("duration must contain at least one component")

    total = Decimal(0)
    total += _decimal_value(date_match, "years") * _SECONDS_PER_YEAR
    total += _decimal_value(date_match, "months") * _SECONDS_PER_MONTH
    total += _decimal_value(date_match, "weeks") * _SECONDS_PER_WEEK
    total += _decimal_value(date_match, "days") * _SECONDS_PER_DAY

    total += _decimal_value(time_match, "hours") * _SECONDS_PER_HOUR
    total += _decimal_value(time_match, "minutes") * _SECONDS_PER_MINUTE
    total += _decimal_value(time_match, "seconds")

    if sign < 0 and total != 0:
        total = -total

    try:
        return float(total)
    except OverflowError:
        return float("-inf") if sign < 0 else float("inf")


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
