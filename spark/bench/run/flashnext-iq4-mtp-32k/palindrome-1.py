def longest_palindrome(s: str) -> str:
    n = len(s)
    if n == 0:
        return ""

    best_start = 0
    best_len = 1

    def expand(left: int, right: int) -> None:
        nonlocal best_start, best_len

        while left >= 0 and right < n and s[left] == s[right]:
            current_len = right - left + 1

            if current_len > best_len or (current_len == best_len and left < best_start):
                best_len = current_len
                best_start = left

            left -= 1
            right += 1

    for center in range(n):
        expand(center, center)
        expand(center, center + 1)

    return s[best_start:best_start + best_len]


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
