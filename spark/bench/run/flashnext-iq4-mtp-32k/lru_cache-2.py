from collections import OrderedDict

class LRUCache:
    def __init__(self, capacity: int):
        self.capacity = capacity
        self.cache = OrderedDict()

    def get(self, key) -> int:
        if key not in self.cache:
            return -1

        self.cache.move_to_end(key)
        return self.cache[key]

    def put(self, key, value) -> None:
        if self.capacity <= 0:
            return

        if key in self.cache:
            self.cache.move_to_end(key)

        self.cache[key] = value

        if len(self.cache) > self.capacity:
            self.cache.popitem(last=False)


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
