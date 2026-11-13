_DIGITS = frozenset("0123456789")
_PRE_BUILD_CHARS = _DIGITS | frozenset(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-"
)

def _is_ascii_digits(text: str) -> bool:
    return bool(text) and all(ch in _DIGITS for ch in text)

def _is_valid_core_identifier(text: str) -> bool:
    return _is_ascii_digits(text) and (text == "0" or text[0] != "0")

def _is_valid_prerelease_identifier(text: str) -> bool:
    if not text:
        return False
    all_digits = True
    for ch in text:
        if ch in _DIGITS:
            continue
        all_digits = False
        if ch not in _PRE_BUILD_CHARS:
            return False
    if all_digits:
        return text == "0" or text[0] != "0"
    return True

def _is_valid_build_identifier(text: str) -> bool:
    return bool(text) and all(ch in _PRE_BUILD_CHARS for ch in text)

def _parse_version(version: str):
    if not isinstance(version, str):
        raise ValueError(f"Invalid semantic version: {version!r}")

    plus_parts = version.split("+")
    if len(plus_parts) > 2:
        raise ValueError(f"Invalid semantic version: {version!r}")

    main, build = (plus_parts[0], None) if len(plus_parts) == 1 else (plus_parts[0], plus_parts[1])

    if build is not None:
        for segment in build.split("."):
            if not _is_valid_build_identifier(segment):
                raise ValueError(f"Invalid semantic version: {version!r}")

    if "-" in main:
        core_text, prerelease_text = main.split("-", 1)
        if not prerelease_text:
            raise ValueError(f"Invalid semantic version: {version!r}")
        prerelease = prerelease_text.split(".")
        for segment in prerelease:
            if not _is_valid_prerelease_identifier(segment):
                raise ValueError(f"Invalid semantic version: {version!r}")
    else:
        core_text = main
        prerelease = None

    core_parts = core_text.split(".")
    if len(core_parts) != 3:
        raise ValueError(f"Invalid semantic version: {version!r}")
    for segment in core_parts:
        if not _is_valid_core_identifier(segment):
            raise ValueError(f"Invalid semantic version: {version!r}")

    return (int(core_parts[0]), int(core_parts[1]), int(core_parts[2])), prerelease

def _compare_identifiers(left: str, right: str) -> int:
    left_numeric = all(ch in _DIGITS for ch in left)
    right_numeric = all(ch in _DIGITS for ch in right)
    if left_numeric and right_numeric:
        left_val = int(left)
        right_val = int(right)
        return -1 if left_val < right_val else (1 if left_val > right_val else 0)
    if left_numeric != right_numeric:
        return -1 if left_numeric else 1
    return -1 if left < right else (1 if left > right else 0)

def _compare_prereleases(left, right) -> int:
    if left is None and right is None:
        return 0
    if left is None:
        return 1
    if right is None:
        return -1
    for l_id, r_id in zip(left, right):
        cmp = _compare_identifiers(l_id, r_id)
        if cmp != 0:
            return cmp
    if len(left) < len(right):
        return -1
    if len(left) > len(right):
        return 1
    return 0

def compare_semver(a: str, b: str) -> int:
    core_a, prerelease_a = _parse_version(a)
    core_b, prerelease_b = _parse_version(b)
    if core_a != core_b:
        return -1 if core_a < core_b else 1
    return _compare_prereleases(prerelease_a, prerelease_b)


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
