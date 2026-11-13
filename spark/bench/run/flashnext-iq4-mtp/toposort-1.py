from __future__ import annotations

import heapq


def toposort(deps: dict[str, set[str]]) -> list[str]:
    nodes: set[str] = set(deps)
    indegree: dict[str, int] = {}
    dependents: dict[str, list[str]] = {}

    for node, dependencies in deps.items():
        indegree.setdefault(node, 0)
        dependents.setdefault(node, [])

        for dependency in dependencies:
            nodes.add(dependency)
            indegree.setdefault(dependency, 0)
            dependents.setdefault(dependency, []).append(node)
            indegree[node] += 1

    for node in nodes:
        indegree.setdefault(node, 0)
        dependents.setdefault(node, [])

    heap = [node for node in nodes if indegree[node] == 0]
    heapq.heapify(heap)

    order: list[str] = []

    while heap:
        node = heapq.heappop(heap)
        order.append(node)

        for dependent in dependents[node]:
            indegree[dependent] -= 1
            if indegree[dependent] == 0:
                heapq.heappush(heap, dependent)

    if len(order) != len(nodes):
        raise ValueError("cycle detected")

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
