def full_justify(words: list[str], width: int) -> list[str]:
    if not words:
        return []

    result = []
    n = len(words)
    start = 0

    while start < n:
        end = start + 1
        line_len = len(words[start])

        while end < n and line_len + 1 + len(words[end]) <= width:
            line_len += 1 + len(words[end])
            end += 1

        if end == n:
            result.append(" ".join(words[start:end]).ljust(width))
        elif end - start == 1:
            result.append(words[start].ljust(width))
        else:
            word_len = sum(len(word) for word in words[start:end])
            gaps = end - start - 1
            extra_spaces = width - word_len - gaps
            base, remainder = divmod(extra_spaces, gaps)

            line = []
            for i in range(start, end):
                line.append(words[i])
                if i < end - 1:
                    spaces = 1 + base + (1 if i - start < remainder else 0)
                    line.append(" " * spaces)

            result.append("".join(line))

        start = end

    return result


# ---- tests ----
assert full_justify(['This','is','an','example','of','text','justification.'], 16) == ['This    is    an','example  of text','justification.  ']
assert full_justify(['What','must','be','acknowledgment','shall','be'], 16) == ['What   must   be','acknowledgment  ','shall be        ']
assert full_justify(['a'], 3) == ['a  ']
assert full_justify(['ab','cd','ef'], 5) == ['ab cd','ef   ']
