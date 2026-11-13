from __future__ import annotations

import heapq


def toposort(deps: dict[str, set[str]]) -> list[str]:
    nodes: set[str] = set(deps)
    for dependency_set in deps.values():
        nodes.update(dependency_set)

    indegree = {node: 0 for node in nodes}
    dependents: dict[str, set[str]] = {node: set() for node in nodes}

    for node, dependencies in deps.items():
        for dependency in dependencies:
            dependents[dependency].add(node)
            indegree[node] += 1

    ready = [node for node in nodes if indegree[node] == 0]
    heapq.heapify(ready)

    order: list[str] = []
    while ready:
        node = heapq.heappop(ready)
        order.append(node)

        for dependent in dependents[node]:
            indegree[dependent] -= 1
            if indegree[dependent] == 0:
                heapq.heappush(ready, dependent)

    if len(order) != len(nodes):
        raise ValueError("Dependency graph contains a cycle")

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
