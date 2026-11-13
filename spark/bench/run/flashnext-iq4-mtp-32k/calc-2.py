def evaluate(expr: str) -> float:
    def precedence(op: str) -> int:
        if op == '+' or op == '-':
            return 1
        if op == '*' or op == '/':
            return 2
        if op == 'u+' or op == 'u-':
            return 3
        raise ValueError("unknown operator")

    output = []
    ops = []
    expecting_operand = True
    i = 0
    n = len(expr)

    while i < n:
        ch = expr[i]
        if ch.isspace():
            i += 1
            continue

        if '0' <= ch <= '9' or ch == '.':
            if not expecting_operand:
                raise ValueError("unexpected number")
            start = i
            has_digit = False
            has_dot = False
            while i < n:
                c = expr[i]
                if '0' <= c <= '9':
                    has_digit = True
                    i += 1
                elif c == '.':
                    if has_dot:
                        break
                    has_dot = True
                    i += 1
                else:
                    break
            if not has_digit:
                raise ValueError("malformed number")
            try:
                value = float(expr[start:i])
            except ValueError as exc:
                raise ValueError("malformed number") from exc
            output.append(value)
            expecting_operand = False
            continue

        if ch == '(':
            if not expecting_operand:
                raise ValueError("unexpected '('")
            ops.append(ch)
            i += 1
            continue

        if ch == ')':
            if expecting_operand:
                raise ValueError("unexpected ')'")
            while ops and ops[-1] != '(':
                output.append(ops.pop())
            if not ops or ops[-1] != '(':
                raise ValueError("unbalanced parentheses")
            ops.pop()
            expecting_operand = False
            continue

        if ch == '+' or ch == '-':
            if expecting_operand:
                ops.append('u' + ch)
            else:
                while ops and ops[-1] != '(' and precedence(ops[-1]) >= 1:
                    output.append(ops.pop())
                ops.append(ch)
                expecting_operand = True
            i += 1
            continue

        if ch == '*' or ch == '/':
            if expecting_operand:
                raise ValueError("unexpected operator")
            while ops and ops[-1] != '(' and precedence(ops[-1]) >= 2:
                output.append(ops.pop())
            ops.append(ch)
            expecting_operand = True
            i += 1
            continue

        raise ValueError("invalid character")

    if expecting_operand:
        raise ValueError("incomplete expression")

    while ops:
        op = ops.pop()
        if op == '(':
            raise ValueError("unbalanced parentheses")
        output.append(op)

    stack = []
    for token in output:
        if isinstance(token, float):
            stack.append(token)
        elif token == 'u+':
            if not stack:
                raise ValueError("malformed expression")
            stack.append(stack.pop())
        elif token == 'u-':
            if not stack:
                raise ValueError("malformed expression")
            stack.append(-stack.pop())
        elif token in ('+', '-', '*', '/'):
            if len(stack) < 2:
                raise ValueError("malformed expression")
            rhs = stack.pop()
            lhs = stack.pop()
            if token == '+':
                stack.append(lhs + rhs)
            elif token == '-':
                stack.append(lhs - rhs)
            elif token == '*':
                stack.append(lhs * rhs)
            else:
                stack.append(lhs / rhs)
        else:
            raise ValueError("unknown token")

    if len(stack) != 1:
        raise ValueError("malformed expression")
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
