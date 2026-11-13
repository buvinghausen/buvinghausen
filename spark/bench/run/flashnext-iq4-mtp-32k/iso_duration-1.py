def parse_duration(s: str) -> float:
    """
    Parse a simplified ISO-8601 duration string into total seconds.

    Supported form:
        P[<years>Y][<months>M][<weeks>W][<days>D][T[<hours>H][<minutes>M][<seconds>S]]

    An optional leading '-' makes the duration negative.
    Fractional numeric components are supported, e.g. PT0.5H.
    """
    if not isinstance(s, str):
        raise ValueError("duration must be a string")

    if not s:
        raise ValueError("duration string must not be empty")

    negative = False
    if s[0] == "-":
        negative = True
        s = s[1:]

    if not s or s[0] != "P":
        raise ValueError("duration must start with P")

    body = s[1:]

    if not body:
        raise ValueError("duration must contain at least one component")

    if body.count("T") > 1:
        raise ValueError("duration may contain at most one T")

    if "T" in body:
        date_part, time_part = body.split("T", 1)
        if not time_part:
            raise ValueError("a time part is required after T")
    else:
        date_part, time_part = body, ""

    if not date_part and not time_part:
        raise ValueError("duration must contain at least one component")

    digits = frozenset("0123456789")

    date_order = ("Y", "M", "W", "D")
    time_order = ("H", "M", "S")

    date_seconds = {
        "Y": 365.0 * 86400.0,
        "M": 30.0 * 86400.0,
        "W": 7.0 * 86400.0,
        "D": 86400.0,
    }

    time_seconds = {
        "H": 3600.0,
        "M": 60.0,
        "S": 1.0,
    }

    def parse_section(part: str, order, unit_secs: dict) -> float:
        total = 0.0
        i = 0
        last_index = -1
        n = len(part)

        while i < n:
            if part[i] not in digits:
                raise ValueError("duration components must start with a number")

            start = i
            while i < n and part[i] in digits:
                i += 1

            # Allow optional decimal fractions such as 0.5 or 12.25,
            # but reject trailing dots such as 1.
            if i < n and part[i] == ".":
                if i + 1 < n and part[i + 1] in digits:
                    i += 1
                    while i < n and part[i] in digits:
                        i += 1
                else:
                    raise ValueError("invalid decimal number")

            value = float(part[start:i])

            if i == n:
                raise ValueError("number must be followed by a unit")

            unit = part[i]
            try:
                idx = order.index(unit)
            except ValueError:
                raise ValueError(f"unexpected unit: {unit}") from None

            if idx <= last_index:
                raise ValueError("duration components are out of order")

            total += value * unit_secs[unit]
            last_index = idx
            i += 1

        return total

    seconds = 0.0

    if date_part:
        seconds += parse_section(date_part, date_order, date_seconds)

    if time_part:
        seconds += parse_section(time_part, time_order, time_seconds)

    if negative and seconds != 0.0:
        seconds = -seconds

    return seconds


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
