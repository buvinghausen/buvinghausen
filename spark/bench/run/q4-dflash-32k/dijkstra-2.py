import heapq

def shortest_path(graph: dict[str, dict[str, float]], start: str, goal: str) -> tuple[float, list[str]]:
    if start == goal:
        return 0.0, [start]

    INF = float('inf')
    dist = {start: 0.0}
    prev = {}
    heap = [(0.0, start)]

    while heap:
        cost, node = heapq.heappop(heap)

        if cost > dist.get(node, INF):
            continue

        if node == goal:
            path = []
            current = goal
            while current is not None:
                path.append(current)
                current = prev.get(current)
            path.reverse()

            if path and path[-1] == start:
                return float(cost), path
            return INF, []

        for neighbor, weight in graph.get(node, {}).items():
            new_cost = cost + weight
            if new_cost < dist.get(neighbor, INF):
                dist[neighbor] = new_cost
                prev[neighbor] = node
                heapq.heappush(heap, (new_cost, neighbor))

    return INF, []


# ---- tests ----
g = {'a': {'b': 1, 'c': 4}, 'b': {'c': 2, 'd': 5}, 'c': {'d': 1}}
assert shortest_path(g, 'a', 'd') == (4, ['a','b','c','d'])
assert shortest_path(g, 'a', 'a') == (0, ['a'])
assert shortest_path(g, 'd', 'a') == (float('inf'), [])
assert shortest_path(g, 'a', 'zz') == (float('inf'), [])
g2 = {'s': {'t': 10, 'm': 1}, 'm': {'t': 1}}
assert shortest_path(g2, 's', 't') == (2, ['s','m','t'])
