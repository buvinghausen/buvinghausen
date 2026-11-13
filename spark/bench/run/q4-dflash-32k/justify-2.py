def full_justify(words: list[str], width: int) -> list[str]:
    lines: list[str] = []
    i, n = 0, len(words)

    while i < n:
        j = i
        used = len(words[i])

        while j + 1 < n and used + 1 + len(words[j + 1]) <= width:
            j += 1
            used += 1 + len(words[j])

        line_words = words[i:j + 1]

        if j == n - 1 or len(line_words) == 1:
            line = " ".join(line_words)
            lines.append(line + " " * (width - len(line)))
        else:
            total_spaces = width - sum(len(word) for word in line_words)
            gaps = len(line_words) - 1
            base_spaces = total_spaces // gaps
            extra_spaces = total_spaces % gaps

            parts = [line_words[0]]
            for idx, word in enumerate(line_words[1:], start=1):
                spaces = base_spaces + (1 if idx <= extra_spaces else 0)
                parts.append(" " * spaces + word)

            lines.append("".join(parts))

        i = j + 1

    return lines


# ---- tests ----
assert full_justify(['This','is','an','example','of','text','justification.'], 16) == ['This    is    an','example  of text','justification.  ']
assert full_justify(['What','must','be','acknowledgment','shall','be'], 16) == ['What   must   be','acknowledgment  ','shall be        ']
assert full_justify(['a'], 3) == ['a  ']
assert full_justify(['ab','cd','ef'], 5) == ['ab cd','ef   ']
