def full_justify(words: list[str], width: int) -> list[str]:
    lines: list[str] = []
    n = len(words)
    i = 0

    while i < n:
        line: list[str] = []
        used = 0

        while i < n:
            word = words[i]

            if not line:
                line.append(word)
                used = len(word)
                i += 1
                continue

            if used + 1 + len(word) <= width:
                line.append(word)
                used += 1 + len(word)
                i += 1
            else:
                break

        if i == n or len(line) == 1:
            line_str = " ".join(line)
            lines.append(line_str + " " * (width - len(line_str)))
        else:
            gaps = len(line) - 1
            word_len = sum(len(word) for word in line)
            total_spaces = width - word_len

            base_spaces = total_spaces // gaps
            extra_spaces = total_spaces % gaps

            justified_parts: list[str] = []
            for gap_index, word in enumerate(line):
                justified_parts.append(word)

                if gap_index < gaps:
                    spaces = base_spaces + (1 if gap_index < extra_spaces else 0)
                    justified_parts.append(" " * spaces)

            lines.append("".join(justified_parts))

    return lines


# ---- tests ----
assert full_justify(['This','is','an','example','of','text','justification.'], 16) == ['This    is    an','example  of text','justification.  ']
assert full_justify(['What','must','be','acknowledgment','shall','be'], 16) == ['What   must   be','acknowledgment  ','shall be        ']
assert full_justify(['a'], 3) == ['a  ']
assert full_justify(['ab','cd','ef'], 5) == ['ab cd','ef   ']
