def longest_palindrome(s: str) -> str:
    n = len(s)
    if n == 0:
        return ""

    best_start = 0
    best_len = 1

    for i in range(n):
        # Odd-length palindromes centered at i
        left = i
        right = i
        while left >= 0 and right < n and s[left] == s[right]:
            left -= 1
            right += 1

        cur_len = right - left - 1
        if cur_len > best_len:
            best_start = left + 1
            best_len = cur_len

        # Even-length palindromes centered between i and i + 1
        left = i
        right = i + 1
        while left >= 0 and right < n and s[left] == s[right]:
            left -= 1
            right += 1

        cur_len = right - left - 1
        if cur_len > best_len:
            best_start = left + 1
            best_len = cur_len

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
