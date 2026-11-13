from typing import Optional, Any


class Node:
    def __init__(self, key: Any = None, value: Any = None) -> None:
        self.key = key
        self.value = value
        self.prev: Optional["Node"] = None
        self.next: Optional["Node"] = None


class LRUCache:
    def __init__(self, capacity: int) -> None:
        self.capacity = max(0, int(capacity))
        self.cache: dict[Any, Node] = {}

        self.head = Node()
        self.tail = Node()
        self.head.next = self.tail
        self.tail.prev = self.head

    def _remove_node(self, node: Node) -> None:
        prev_node = node.prev
        next_node = node.next
        prev_node.next = next_node
        next_node.prev = prev_node

    def _add_node_to_front(self, node: Node) -> None:
        node.prev = self.head
        node.next = self.head.next
        self.head.next.prev = node
        self.head.next = node

    def _move_to_front(self, node: Node) -> None:
        self._remove_node(node)
        self._add_node_to_front(node)

    def get(self, key: Any) -> int:
        if key not in self.cache:
            return -1

        node = self.cache[key]
        self._move_to_front(node)
        return int(node.value)

    def put(self, key: Any, value: Any) -> None:
        if self.capacity == 0:
            return

        if key in self.cache:
            node = self.cache[key]
            node.value = value
            self._move_to_front(node)
            return

        if len(self.cache) >= self.capacity:
            lru_node = self.tail.prev
            self._remove_node(lru_node)
            del self.cache[lru_node.key]

        new_node = Node(key, value)
        self.cache[key] = new_node
        self._add_node_to_front(new_node)


# ---- tests ----
c = LRUCache(2)
c.put(1, 1); c.put(2, 2)
assert c.get(1) == 1
c.put(3, 3)
assert c.get(2) == -1
c.put(4, 4)
assert c.get(1) == -1
assert c.get(3) == 3
assert c.get(4) == 4
c = LRUCache(1)
c.put(1, 1); c.put(1, 5)
assert c.get(1) == 5
c.put(2, 2)
assert c.get(1) == -1 and c.get(2) == 2
c = LRUCache(2)
c.put(1,1); c.put(2,2); c.put(1,10); c.put(3,3)
assert c.get(2) == -1 and c.get(1) == 10
