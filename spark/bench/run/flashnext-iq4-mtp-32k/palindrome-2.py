def longest_palindrome(s: str) -> str:
    n = len(s)
    if n == 0:
        return ""

    best_start = 0
    best_len = 1

    for center in range(n):
        # Odd-length palindromes centered at `center`
        left = center
        right = center
        while left >= 0 and right < n and s[left] == s[right]:
            left -= 1
            right += 1

        start = left + 1
        length = right - left - 1

        if length > best_len or (length == best_len and start < best_start):
            best_start = start
            best_len = length
            if best_len == n:
                return s

        # Even-length palindromes centered between `center` and `center + 1`
        left = center
        right = center + 1
        while left >= 0 and right < n and s[left] == s[right]:
            left -= 1
            right += 1

        length = right - left - 1
        if length > 0:
            start = left + 1
            if length > best_len or (length == best_len and start < best_start):
                best_start = start
                best_len = length
                if best_len == n:
                    return s

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
