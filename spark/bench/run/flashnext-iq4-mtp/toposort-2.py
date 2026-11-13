from __future__ import annotations

import heapq


def toposort(deps: dict[str, set[str]]) -> list[str]:
    nodes = set(deps.keys())
    for prerequisites in deps.values():
        nodes.update(prerequisites)

    dependents = {node: set() for node in nodes}
    indegree = {node: 0 for node in nodes}

    for node, prerequisites in deps.items():
        for prerequisite in prerequisites:
            if node not in dependents[prerequisite]:
                dependents[prerequisite].add(node)
                indegree[node] += 1

    available = [node for node in nodes if indegree[node] == 0]
    heapq.heapify(available)

    order = []
    while available:
        node = heapq.heappop(available)
        order.append(node)

        for dependent in dependents[node]:
            indegree[dependent] -= 1
            if indegree[dependent] == 0:
                heapq.heappush(available, dependent)

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
