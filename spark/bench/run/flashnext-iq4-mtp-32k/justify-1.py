def full_justify(words: list[str], width: int) -> list[str]:
    if not words:
        return []

    result: list[str] = []
    i = 0
    n = len(words)

    while i < n:
        current_len = len(words[i])
        j = i + 1

        while j < n and current_len + 1 + len(words[j]) <= width:
            current_len += 1 + len(words[j])
            j += 1

        line_words = words[i:j]
        word_count = len(line_words)

        if j == n:
            line = " ".join(line_words)
            result.append(line + " " * (width - len(line)))
        else:
            if word_count == 1:
                result.append(line_words[0] + " " * (width - len(line_words[0])))
            else:
                total_spaces = width - sum(len(word) for word in line_words)
                gaps = word_count - 1
                base_spaces, extra = divmod(total_spaces, gaps)

                line = ""
                for idx, word in enumerate(line_words):
                    line += word
                    if idx != word_count - 1:
                        spaces = base_spaces + (1 if idx < extra else 0)
                        line += " " * spaces

                result.append(line)

        i = j

    return result


# ---- tests ----
assert full_justify(['This','is','an','example','of','text','justification.'], 16) == ['This    is    an','example  of text','justification.  ']
assert full_justify(['What','must','be','acknowledgment','shall','be'], 16) == ['What   must   be','acknowledgment  ','shall be        ']
assert full_justify(['a'], 3) == ['a  ']
assert full_justify(['ab','cd','ef'], 5) == ['ab cd','ef   ']
