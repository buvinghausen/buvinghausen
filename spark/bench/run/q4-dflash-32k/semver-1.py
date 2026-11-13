import re

_NUMERIC = r"(?:0|[1-9][0-9]*)"
_PRERELEASE_IDENT = r"(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
_BUILD_IDENT = r"[0-9A-Za-z-]+"

_SEMVER_RE = re.compile(
    rf"(?P<major>{_NUMERIC})\.(?P<minor>{_NUMERIC})\.(?P<patch>{_NUMERIC})"
    rf"(?P<pre>-{_PRERELEASE_IDENT}(?:\.{_PRERELEASE_IDENT})*)?"
    rf"(?P<build>\+{_BUILD_IDENT}(?:\.{_BUILD_IDENT})*)?"
)

_NUMERIC_RE = re.compile(r"[0-9]+")


def _sign(x, y):
    return (x > y) - (x < y)


def _compare_numeric(x, y):
    x = x.lstrip("0") or "0"
    y = y.lstrip("0") or "0"

    if len(x) != len(y):
        return -1 if len(x) < len(y) else 1

    return _sign(x, y)


def _is_numeric_identifier(ident):
    return _NUMERIC_RE.fullmatch(ident) is not None


def _compare_pre_identifier(a, b):
    a_is_numeric = _is_numeric_identifier(a)
    b_is_numeric = _is_numeric_identifier(b)

    if a_is_numeric and b_is_numeric:
        return _compare_numeric(a, b)

    if a_is_numeric:
        return -1

    if b_is_numeric:
        return 1

    return _sign(a, b)


def _parse_semver(version):
    if not isinstance(version, str):
        raise ValueError("version must be a string")

    match = _SEMVER_RE.fullmatch(version)
    if match is None:
        raise ValueError(f"invalid SemVer version: {version!r}")

    pre = match.group("pre")
    pre_ids = pre[1:].split(".") if pre is not None else None

    return (
        match.group("major"),
        match.group("minor"),
        match.group("patch"),
        pre_ids,
    )


def compare_semver(a: str, b: str) -> int:
    a_major, a_minor, a_patch, a_pre = _parse_semver(a)
    b_major, b_minor, b_patch, b_pre = _parse_semver(b)

    for a_part, b_part in (
        (a_major, b_major),
        (a_minor, b_minor),
        (a_patch, b_patch),
    ):
        result = _compare_numeric(a_part, b_part)
        if result != 0:
            return result

    if a_pre is None and b_pre is None:
        return 0

    if a_pre is None:
        return 1

    if b_pre is None:
        return -1

    for a_id, b_id in zip(a_pre, b_pre):
        result = _compare_pre_identifier(a_id, b_id)
        if result != 0:
            return result

    return _sign(len(a_pre), len(b_pre))


# ---- tests ----
assert compare_semver('1.0.0', '1.0.0') == 0
assert compare_semver('1.0.0', '2.0.0') == -1
assert compare_semver('1.10.0', '1.9.0') == 1
chain = ['1.0.0-alpha','1.0.0-alpha.1','1.0.0-alpha.beta','1.0.0-beta','1.0.0-beta.2','1.0.0-beta.11','1.0.0-rc.1','1.0.0']
for x, y in zip(chain, chain[1:]):
    assert compare_semver(x, y) == -1, (x, y)
    assert compare_semver(y, x) == 1, (y, x)
assert compare_semver('1.0.0+build.1', '1.0.0+build.2') == 0
assert compare_semver('1.0.0-alpha+x', '1.0.0-alpha') == 0
for bad in ['1.2', '01.2.3', '1.2.3-', 'a.b.c', '1.2.3-01']:
    try:
        compare_semver(bad, '1.0.0')
    except ValueError:
        pass
    else:
        raise AssertionError(bad)
