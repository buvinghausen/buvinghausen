from __future__ import annotations

import heapq


def toposort(deps: dict[str, set[str]]) -> list[str]:
    nodes: set[str] = set(deps)
    for required in deps.values():
        nodes.update(required)

    indegree: dict[str, int] = {node: 0 for node in nodes}
    dependents: dict[str, list[str]] = {node: [] for node in nodes}

    for node, required in deps.items():
        unique_required = set(required)
        indegree[node] = len(unique_required)
        for dep in unique_required:
            dependents[dep].append(node)

    available = [node for node, degree in indegree.items() if degree == 0]
    heapq.heapify(available)

    order: list[str] = []
    while available:
        node = heapq.heappop(available)
        order.append(node)

        for dependent in dependents[node]:
            indegree[dependent] -= 1
            if indegree[dependent] == 0:
                heapq.heappush(available, dependent)

    if len(order) != len(nodes):
        raise ValueError("Cycle detected in dependencies")

    return order


# ---- tests ----
assert toposort({}) == []
assert toposort({'b': {'a'}, 'c': {'a'}}) == ['a', 'b', 'c']
assert toposort({'d': {'b','c'}, 'b': {'a'}, 'c': {'a'}}) == ['a','b','c','d']
assert toposort({'x': set(), 'a': set()}) == ['a','x']
assert toposort({'c': {'b'}, 'b': {'a'}, 'z': set()}) == ['a','b','c','z']
for cyc in [{'a': {'b'}, 'b': {'a'}}, {'a': {'a'}}, {'a': {'b'}, 'b': {'c'}, 'c': {'a'}}]:
    try:
        toposort(cyc)
    except ValueError:
        pass
    else:
        raise AssertionError('no cycle detected')
