import re
from typing import List, Optional, Tuple

_DIGITS_RE = re.compile(r"[0-9]+")
_SEMVER_ID_RE = re.compile(r"[0-9A-Za-z-]+")


def _validate_core_part(part: str) -> str:
    if not part or not _DIGITS_RE.fullmatch(part):
        raise ValueError("Invalid SemVer numeric identifier")
    if len(part) > 1 and part[0] == "0":
        raise ValueError("Numeric identifiers must not contain leading zeroes")
    return part


def _validate_pre_identifier(identifier: str) -> str:
    if not identifier or not _SEMVER_ID_RE.fullmatch(identifier):
        raise ValueError("Invalid SemVer pre-release identifier")
    if _DIGITS_RE.fullmatch(identifier) and len(identifier) > 1 and identifier[0] == "0":
        raise ValueError("Numeric pre-release identifiers must not contain leading zeroes")
    return identifier


def _parse_version(version: str) -> Tuple[str, str, str, Optional[List[str]]]:
    if not isinstance(version, str):
        raise ValueError("SemVer version must be a string")

    if "+" in version:
        core_pre, build = version.split("+", 1)
        if not build or any(
            not part or not _SEMVER_ID_RE.fullmatch(part)
            for part in build.split(".")
        ):
            raise ValueError("Invalid SemVer build metadata")
    else:
        core_pre = version

    if "-" in core_pre:
        core, pre = core_pre.split("-", 1)
    else:
        core, pre = core_pre, None

    parts = core.split(".")
    if len(parts) != 3:
        raise ValueError("Invalid SemVer version core")

    major, minor, patch = (_validate_core_part(p) for p in parts)

    if pre is None:
        return major, minor, patch, None

    if pre == "":
        raise ValueError("Empty pre-release identifier")

    pre_identifiers = pre.split(".")
    for identifier in pre_identifiers:
        _validate_pre_identifier(identifier)

    return major, minor, patch, pre_identifiers


def _compare_numeric_identifiers(a: str, b: str) -> int:
    if len(a) != len(b):
        return -1 if len(a) < len(b) else 1
    if a < b:
        return -1
    if a > b:
        return 1
    return 0


def _compare_pre_release_identifiers(
    a: Optional[List[str]],
    b: Optional[List[str]],
) -> int:
    if a is None and b is None:
        return 0
    if a is None:
        return 1
    if b is None:
        return -1

    for left, right in zip(a, b):
        left_numeric = bool(_DIGITS_RE.fullmatch(left))
        right_numeric = bool(_DIGITS_RE.fullmatch(right))

        if left_numeric != right_numeric:
            return -1 if left_numeric else 1

        if left_numeric:
            cmp = _compare_numeric_identifiers(left, right)
            if cmp != 0:
                return cmp
        else:
            if left != right:
                return -1 if left < right else 1

    if len(a) < len(b):
        return -1
    if len(a) > len(b):
        return 1
    return 0


def compare_semver(a: str, b: str) -> int:
    parsed_a = _parse_version(a)
    parsed_b = _parse_version(b)

    for left, right in zip(parsed_a[:3], parsed_b[:3]):
        cmp = _compare_numeric_identifiers(left, right)
        if cmp != 0:
            return cmp

    return _compare_pre_release_identifiers(parsed_a[3], parsed_b[3])


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
