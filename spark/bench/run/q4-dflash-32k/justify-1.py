from __future__ import annotations


def full_justify(words: list[str], width: int) -> list[str]:
    if not words:
        return []

    result: list[str] = []
    i = 0
    n = len(words)

    while i < n:
        j = i
        line_length = len(words[i])

        while (
            j + 1 < n
            and line_length + 1 + len(words[j + 1]) <= width
        ):
            line_length += 1 + len(words[j + 1])
            j += 1

        if j == n - 1 or j == i:
            line = " ".join(words[i:j + 1])
            result.append(line.ljust(width))
        else:
            word_count = j - i + 1
            gaps = word_count - 1
            sum_words = sum(len(w) for w in words[i:j + 1])
            total_spaces = width - sum_words

            base_spaces = total_spaces // gaps
            extra_spaces = total_spaces % gaps

            line = words[i]
            for k in range(gaps):
                spaces = base_spaces + (1 if k < extra_spaces else 0)
                line += " " * spaces + words[i + k + 1]

            result.append(line)

        i = j + 1

    return result


# ---- tests ----
assert full_justify(['This','is','an','example','of','text','justification.'], 16) == ['This    is    an','example  of text','justification.  ']
assert full_justify(['What','must','be','acknowledgment','shall','be'], 16) == ['What   must   be','acknowledgment  ','shall be        ']
assert full_justify(['a'], 3) == ['a  ']
assert full_justify(['ab','cd','ef'], 5) == ['ab cd','ef   ']
