def merge(intervals: list[list[int]]) -> list[list[int]]:
    if not intervals:
        return []

    sorted_intervals = sorted(intervals, key=lambda interval: (interval[0], interval[1]))
    merged = [[sorted_intervals[0][0], sorted_intervals[0][1]]]

    for start, end in sorted_intervals[1:]:
        if start <= merged[-1][1]:
            if end > merged[-1][1]:
                merged[-1][1] = end
        else:
            merged.append([start, end])

    return merged


# ---- tests ----
assert merge([]) == []
assert merge([[1,3],[2,6],[8,10],[15,18]]) == [[1,6],[8,10],[15,18]]
assert merge([[1,4],[4,5]]) == [[1,5]]
assert merge([[5,7],[1,2]]) == [[1,2],[5,7]]
assert merge([[1,10],[2,3],[4,5]]) == [[1,10]]
x = [[3,4],[1,2]]
merge(x)
assert x == [[3,4],[1,2]]
