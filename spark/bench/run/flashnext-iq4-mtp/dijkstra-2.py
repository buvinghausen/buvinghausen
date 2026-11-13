import heapq

def shortest_path(graph: dict[str, dict[str, float]], start: str, goal: str) -> tuple[float, list[str]]:
    if start == goal:
        return (0.0, [start])

    inf = float("inf")
    dist = {start: 0.0}
    prev = {}
    heap = [(0.0, start)]

    while heap:
        cost, node = heapq.heappop(heap)

        if cost > dist.get(node, inf):
            continue

        if node == goal:
            break

        for nxt, weight in graph.get(node, {}).items():
            new_cost = cost + weight
            if new_cost < dist.get(nxt, inf):
                dist[nxt] = new_cost
                prev[nxt] = node
                heapq.heappush(heap, (new_cost, nxt))

    if goal not in dist:
        return (inf, [])

    path = []
    node = goal

    while True:
        path.append(node)
        if node == start:
            break
        if node not in prev:
            return (inf, [])
        node = prev[node]

    path.reverse()
    return (dist[goal], path)


# ---- tests ----
g = {'a': {'b': 1, 'c': 4}, 'b': {'c': 2, 'd': 5}, 'c': {'d': 1}}
assert shortest_path(g, 'a', 'd') == (4, ['a','b','c','d'])
assert shortest_path(g, 'a', 'a') == (0, ['a'])
assert shortest_path(g, 'd', 'a') == (float('inf'), [])
assert shortest_path(g, 'a', 'zz') == (float('inf'), [])
g2 = {'s': {'t': 10, 'm': 1}, 'm': {'t': 1}}
assert shortest_path(g2, 's', 't') == (2, ['s','m','t'])
