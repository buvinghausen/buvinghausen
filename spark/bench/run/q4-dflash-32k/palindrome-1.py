def longest_palindrome(s: str) -> str:
    n = len(s)
    if n == 0:
        return ""

    best_start = 0
    best_len = 0

    # Odd-length palindromes: d1[i] is the radius including the center.
    d1 = [0] * n
    left = 0
    right = -1

    for center in range(n):
        if center > right:
            radius = 1
        else:
            mirror = left + right - center
            radius = min(d1[mirror], right - center + 1)

        while (
            center - radius >= 0
            and center + radius < n
            and s[center - radius] == s[center + radius]
        ):
            radius += 1

        d1[center] = radius

        if center + radius - 1 > right:
            left = center - radius + 1
            right = center + radius - 1

        length = 2 * radius - 1
        start = center - radius + 1

        if length > best_len or (length == best_len and start < best_start):
            best_len = length
            best_start = start

    # Even-length palindromes: d2[i] is half the length, centered between i-1 and i.
    d2 = [0] * n
    left = 0
    right = -1

    for center in range(n):
        if center > right:
            radius = 0
        else:
            mirror = left + right - center + 1
            radius = min(d2[mirror], right - center + 1)

        while (
            center - radius - 1 >= 0
            and center + radius < n
            and s[center - radius - 1] == s[center + radius]
        ):
            radius += 1

        d2[center] = radius

        if center + radius - 1 > right:
            left = center - radius
            right = center + radius - 1

        length = 2 * radius
        if length:
            start = center - radius
            if length > best_len or (length == best_len and start < best_start):
                best_len = length
                best_start = start

    return s[best_start : best_start + best_len]


# ---- tests ----
assert longest_palindrome('') == ''
assert longest_palindrome('a') == 'a'
assert longest_palindrome('babad') == 'bab'
assert longest_palindrome('cbbd') == 'bb'
assert longest_palindrome('abacdfgdcaba') == 'aba'
assert longest_palindrome('forgeeksskeegfor') == 'geeksskeeg'
import time
s = 'ab' * 1500
t = time.time(); r = longest_palindrome(s); assert len(r) == 2999 and time.time() - t < 20
