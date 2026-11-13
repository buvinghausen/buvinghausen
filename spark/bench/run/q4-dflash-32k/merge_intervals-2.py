def merge(intervals: list[list[int]]) -> list[list[int]]:
    result: list[list[int]] = []

    for start, end in sorted(intervals, key=lambda interval: (interval[0], interval[1])):
        if not result or start > result[-1][1]:
            result.append([start, end])
        else:
            result[-1][1] = max(result[-1][1], end)

    return result


# ---- tests ----
assert merge([]) == []
assert merge([[1,3],[2,6],[8,10],[15,18]]) == [[1,6],[8,10],[15,18]]
assert merge([[1,4],[4,5]]) == [[1,5]]
assert merge([[5,7],[1,2]]) == [[1,2],[5,7]]
assert merge([[1,10],[2,3],[4,5]]) == [[1,10]]
x = [[3,4],[1,2]]
merge(x)
assert x == [[3,4],[1,2]]
