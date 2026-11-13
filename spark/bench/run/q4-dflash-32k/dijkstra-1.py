import heapq

def shortest_path(graph: dict[str, dict[str, float]], start: str, goal: str) -> tuple[float, list[str]]:
    if start == goal:
        return 0.0, [start]

    dist = {start: 0.0}
    parent = {start: None}
    visited = set()
    heap = [(0.0, start)]

    while heap:
        cost, node = heapq.heappop(heap)

        if node in visited:
            continue

        visited.add(node)

        if node == goal:
            path = [node]
            current = node
            while current != start:
                current = parent[current]
                path.append(current)
            path.reverse()
            return float(cost), path

        for neighbor, weight in graph.get(node, {}).items():
            new_cost = cost + weight
            if neighbor not in dist or new_cost < dist[neighbor]:
                dist[neighbor] = new_cost
                parent[neighbor] = node
                heapq.heappush(heap, (new_cost, neighbor))

    return float('inf'), []


# ---- tests ----
g = {'a': {'b': 1, 'c': 4}, 'b': {'c': 2, 'd': 5}, 'c': {'d': 1}}
assert shortest_path(g, 'a', 'd') == (4, ['a','b','c','d'])
assert shortest_path(g, 'a', 'a') == (0, ['a'])
assert shortest_path(g, 'd', 'a') == (float('inf'), [])
assert shortest_path(g, 'a', 'zz') == (float('inf'), [])
g2 = {'s': {'t': 10, 'm': 1}, 'm': {'t': 1}}
assert shortest_path(g2, 's', 't') == (2, ['s','m','t'])
