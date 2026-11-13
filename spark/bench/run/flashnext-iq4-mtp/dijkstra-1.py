import heapq

def shortest_path(graph: dict[str, dict[str, float]], start: str, goal: str) -> tuple[float, list[str]]:
    if start == goal:
        return 0.0, [start]

    distances: dict[str, float] = {start: 0.0}
    previous: dict[str, str | None] = {start: None}
    heap: list[tuple[float, str]] = [(0.0, start)]

    while heap:
        current_cost, node = heapq.heappop(heap)

        if current_cost > distances.get(node, float("inf")):
            continue

        if node == goal:
            break

        for neighbor, weight in graph.get(node, {}).items():
            new_cost = current_cost + weight

            if new_cost < distances.get(neighbor, float("inf")):
                distances[neighbor] = new_cost
                previous[neighbor] = node
                heapq.heappush(heap, (new_cost, neighbor))

    if goal not in distances:
        return float("inf"), []

    path: list[str] = []
    current: str | None = goal

    while current is not None:
        path.append(current)
        current = previous.get(current)

    path.reverse()
    return distances[goal], path


# ---- tests ----
g = {'a': {'b': 1, 'c': 4}, 'b': {'c': 2, 'd': 5}, 'c': {'d': 1}}
assert shortest_path(g, 'a', 'd') == (4, ['a','b','c','d'])
assert shortest_path(g, 'a', 'a') == (0, ['a'])
assert shortest_path(g, 'd', 'a') == (float('inf'), [])
assert shortest_path(g, 'a', 'zz') == (float('inf'), [])
g2 = {'s': {'t': 10, 'm': 1}, 'm': {'t': 1}}
assert shortest_path(g2, 's', 't') == (2, ['s','m','t'])
