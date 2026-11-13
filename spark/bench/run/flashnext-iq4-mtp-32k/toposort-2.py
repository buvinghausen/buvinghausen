import heapq


def toposort(deps: dict[str, set[str]]) -> list[str]:
    """
    Return a lexicographically smallest topological ordering of nodes where
    deps[node] contains all prerequisites that must appear before node.

    Raises:
        ValueError: if the dependency graph contains a cycle.
    """
    nodes = set(deps)
    for prereqs in deps.values():
        nodes.update(prereqs)

    indegree = {node: 0 for node in nodes}
    dependents = {node: set() for node in nodes}

    for node, prereqs in deps.items():
        for prereq in prereqs:
            dependents[prereq].add(node)
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
        raise ValueError("Cycle detected in dependency graph")

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
