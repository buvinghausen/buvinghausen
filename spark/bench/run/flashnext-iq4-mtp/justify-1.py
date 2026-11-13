def full_justify(words: list[str], width: int) -> list[str]:
    def justify_line(line: list[str], width: int) -> str:
        if len(line) == 1:
            return line[0].ljust(width)

        words_length = sum(len(word) for word in line)
        spaces = width - words_length
        gaps = len(line) - 1
        base, extra = divmod(spaces, gaps)

        parts = [line[0]]
        for i in range(1, len(line)):
            gap_size = base + (1 if i <= extra else 0)
            parts.append(" " * gap_size)
            parts.append(line[i])

        return "".join(parts)

    result: list[str] = []
    line: list[str] = []
    current_length = 0

    for word in words:
        if not line:
            line = [word]
            current_length = len(word)
        elif current_length + 1 + len(word) <= width:
            line.append(word)
            current_length += 1 + len(word)
        else:
            result.append(justify_line(line, width))
            line = [word]
            current_length = len(word)

    if line:
        result.append(" ".join(line).ljust(width))

    return result


# ---- tests ----
assert full_justify(['This','is','an','example','of','text','justification.'], 16) == ['This    is    an','example  of text','justification.  ']
assert full_justify(['What','must','be','acknowledgment','shall','be'], 16) == ['What   must   be','acknowledgment  ','shall be        ']
assert full_justify(['a'], 3) == ['a  ']
assert full_justify(['ab','cd','ef'], 5) == ['ab cd','ef   ']
