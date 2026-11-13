center = right = 0
for i in range(n):
    if i < right:
        p[i] = min(right - i, p[2*center - i])
    while ...:
        p[i]+=1
    if i + p[i] > right:
        center, right = i, i + p[i]


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
