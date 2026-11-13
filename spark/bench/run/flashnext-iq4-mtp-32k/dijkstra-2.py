from __future__ import annotations

import heapq


def shortest_path(
    graph: dict[str, dict[str, float]],
    start: str,
    goal: str,
) -> tuple[float, list[str]]:
    if start == goal:
        return (0.0, [start])

    distances: dict[str, float] = {start: 0.0}
    previous: dict[str, str] = {}
    priority_queue: list[tuple[float, str]] = [(0.0, start)]

    while priority_queue:
        current_cost, node = heapq.heappop(priority_queue)

        if current_cost > distances.get(node, float("inf")):
            continue

        if node == goal:
            path: list[str] = []
            while True:
                path.append(node)
                if node == start:
                    break
                node = previous[node]
            path.reverse()
            return (current_cost, path)

        for neighbor, weight in graph.get(node, {}).items():
            new_cost = current_cost + weight
            if new_cost < distances.get(neighbor, float("inf")):
                distances[neighbor] = new_cost
                previous[neighbor] = node
                heapq.heappush(priority_queue, (new_cost, neighbor))

    return (float("inf"), [])


# ---- tests ----
g = {'a': {'b': 1, 'c': 4}, 'b': {'c': 2, 'd': 5}, 'c': {'d': 1}}
assert shortest_path(g, 'a', 'd') == (4, ['a','b','c','d'])
assert shortest_path(g, 'a', 'a') == (0, ['a'])
assert shortest_path(g, 'd', 'a') == (float('inf'), [])
assert shortest_path(g, 'a', 'zz') == (float('inf'), [])
g2 = {'s': {'t': 10, 'm': 1}, 'm': {'t': 1}}
assert shortest_path(g2, 's', 't') == (2, ['s','m','t'])
