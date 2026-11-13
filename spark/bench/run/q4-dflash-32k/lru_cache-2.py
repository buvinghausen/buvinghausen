class Node:
    __slots__ = ("key", "value", "prev", "next")

    def __init__(self, key=None, value=None):
        self.key = key
        self.value = value
        self.prev = None
        self.next = None


class LRUCache:
    def __init__(self, capacity: int):
        self.capacity = capacity if capacity > 0 else 0
        self.size = 0
        self.cache = {}

        self.head = Node()
        self.tail = Node()
        self.head.next = self.tail
        self.tail.prev = self.head

    def _add_to_front(self, node: Node) -> None:
        node.prev = self.head
        node.next = self.head.next
        self.head.next.prev = node
        self.head.next = node

    def _remove(self, node: Node) -> None:
        node.prev.next = node.next
        node.next.prev = node.prev
        node.prev = None
        node.next = None

    def _move_to_front(self, node: Node) -> None:
        self._remove(node)
        self._add_to_front(node)

    def get(self, key) -> int:
        node = self.cache.get(key)
        if node is None:
            return -1

        self._move_to_front(node)
        return node.value

    def put(self, key, value) -> None:
        if self.capacity == 0:
            return

        node = self.cache.get(key)
        if node is not None:
            node.value = value
            self._move_to_front(node)
            return

        if self.size == self.capacity:
            lru_node = self.tail.prev
            self._remove(lru_node)
            del self.cache[lru_node.key]

        new_node = Node(key, value)
        self.cache[key] = new_node
        self._add_to_front(new_node)
        self.size += 1


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
