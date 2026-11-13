def _validate_core_part(part):
    if not part: raise ValueError
    if not all(_is_ascii_digit(ch) for ch in part): raise ValueError
    if len(part) > 1 and part[0]=='0': raise ValueError


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
