def evaluate(expr: str) -> float:
    def precedence(op):
        if op in ("+", "-"):
            return 1
        if op in ("*", "/"):
            return 2
        if op in ("u+", "u-"):
            return 3
        return 0

    tokens = []
    ops = []
    i = 0
    n = len(expr)
    expect_operand = True

    while i < n:
        c = expr[i]
        if c.isspace():
            i += 1
            continue

        if c.isdigit() or c == ".":
            if not expect_operand:
                raise ValueError("Unexpected number")
            start = i
            if c == ".":
                if i + 1 >= n or not expr[i + 1].isdigit():
                    raise ValueError("Invalid number")
                i += 1
                while i < n and expr[i].isdigit():
                    i += 1
            else:
                while i < n and expr[i].isdigit():
                    i += 1
                if i < n and expr[i] == ".":
                    i += 1
                    while i < n and expr[i].isdigit():
                        i += 1
            num_str = expr[start:i]
            # num_str should contain at least one digit except maybe? For digit branch yes, dot branch yes.
            tokens.append(("num", float(num_str)))
            expect_operand = False
            continue

        if c == "(":
            if not expect_operand:
                raise ValueError("Unexpected '('")
            ops.append("(")
            # expect_operand remains True
            i += 1
            continue

        if c == ")":
            if expect_operand:
                raise ValueError("Missing expression inside parentheses")
            while ops and ops[-1] != "(":
                tokens.append(("op", ops.pop()))
            if not ops or ops[-1] != "(":
                raise ValueError("Unmatched ')'")
            ops.pop()
            expect_operand = False
            i += 1
            continue

        if c in "+-":
            if expect_operand:
                ops.append("u" + c)
            else:
                while ops and ops[-1] != "(" and precedence(ops[-1]) >= precedence(c):
                    tokens.append(("op", ops.pop()))
                ops.append(c)
                expect_operand = True
            i += 1
            continue

        if c in "*/":
            if expect_operand:
                raise ValueError("Missing operand")
            while ops and ops[-1] != "(" and precedence(ops[-1]) >= precedence(c):
                tokens.append(("op", ops.pop()))
            ops.append(c)
            expect_operand = True
            i += 1
            continue

        raise ValueError(f"Invalid character: {c!r}")

    if expect_operand:
        raise ValueError("Incomplete expression")

    while ops:
        top = ops.pop()
        if top == "(":
            raise ValueError("Unmatched '('")
        tokens.append(("op", top))

    if not tokens:
        raise ValueError("Empty expression")

    stack = []
    for token, val in tokens:
        if token == "num":
            stack.append(val)
        else:
            if val in ("u+", "u-"):
                if not stack:
                    raise ValueError("Missing operand")
                x = stack.pop()
                stack.append(-x if val == "u-" else x)
            else:
                if len(stack) < 2:
                    raise ValueError("Missing operand")
                b = stack.pop()
                a = stack.pop()
                if val == "+":
                    stack.append(a + b)
                elif val == "-":
                    stack.append(a - b)
                elif val == "*":
                    stack.append(a * b)
                elif val == "/":
                    stack.append(a / b)
                else:
                    raise ValueError("Invalid operator")

    if len(stack) != 1:
        raise ValueError("Invalid expression")
    return float(stack[0])


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
