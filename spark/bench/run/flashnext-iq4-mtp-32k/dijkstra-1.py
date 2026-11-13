import heapq

def shortest_path(graph: dict[str, dict[str, float]], start: str, goal: str) -> tuple[float, list[str]]:
    if start == goal:
        return (0.0, [start])

    dist = {start: 0.0}
    prev = {}
    heap = [(0.0, start)]

    while heap:
        current_cost, current_node = heapq.heappop(heap)

        if current_cost > dist.get(current_node, float("inf")):
            continue

        if current_node == goal:
            path = []
            node = goal
            while node != start:
                path.append(node)
                node = prev[node]
            path.append(start)
            path.reverse()
            return (current_cost, path)

        for neighbor, weight in graph.get(current_node, {}).items():
            new_cost = current_cost + weight
            if new_cost < dist.get(neighbor, float("inf")):
                dist[neighbor] = new_cost
                prev[neighbor] = current_node
                heapq.heappush(heap, (new_cost, neighbor))

    return (float("inf"), [])


# ---- tests ----
g = {'a': {'b': 1, 'c': 4}, 'b': {'c': 2, 'd': 5}, 'c': {'d': 1}}
assert shortest_path(g, 'a', 'd') == (4, ['a','b','c','d'])
assert shortest_path(g, 'a', 'a') == (0, ['a'])
assert shortest_path(g, 'd', 'a') == (float('inf'), [])
assert shortest_path(g, 'a', 'zz') == (float('inf'), [])
g2 = {'s': {'t': 10, 'm': 1}, 'm': {'t': 1}}
assert shortest_path(g2, 's', 't') == (2, ['s','m','t'])
