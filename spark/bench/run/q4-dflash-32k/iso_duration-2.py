def parse_duration(s: str, _re=_DURATION_RE) -> float:


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
