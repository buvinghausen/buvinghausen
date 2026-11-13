if not isinstance(expr, str): raise ValueError('expression must be a string')


# ---- tests ----
import math
def close(a,b): return math.isclose(a,b,rel_tol=1e-9,abs_tol=1e-12)
assert close(evaluate('1 + 2 * 3'), 7)
assert close(evaluate('(1 + 2) * 3'), 9)
assert close(evaluate('10 / 4'), 2.5)
assert close(evaluate('8 - 3 - 2'), 3)
assert close(evaluate('2 * -3'), -6)
assert close(evaluate('-(2 + 3) * 2'), -10)
assert close(evaluate(' 1.5 * 2 '), 3)
assert close(evaluate('--4'), 4)
assert close(evaluate('16 / 4 / 2'), 2)
for bad in ['1 +', '(1', '2 3', '', '1 + ()', ')1(']:
    try:
        evaluate(bad)
    except ValueError:
        pass
    else:
        raise AssertionError('accepted ' + repr(bad))
