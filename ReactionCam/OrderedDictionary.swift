struct OrderedDictionary<Key: Hashable, Value> {
    typealias Element = (key: Key, value: Value)

    fileprivate var dictionary = [Key: Value]()
    fileprivate var orderedKeys = [Key]()

    var count: Int {
        return self.orderedKeys.count
    }

    var keys: [Key] {
        return self.orderedKeys
    }

    var values: [Value] {
        return self.orderedKeys.map {
            self.dictionary[$0]!
        }
    }

    subscript(key: Key) -> Value? {
        get {
            return self.dictionary[key]
        }
        set {
            if let value = newValue {
                self.updateValue(value, forKey: key)
            } else {
                self.removeValue(forKey: key)
            }
        }
    }

    init() {
    }

    init<S: Sequence>(_ sequence: S) where S.Iterator.Element == Element {
        self.append(contentsOf: sequence)
    }

    mutating func removeLast() -> Element {
        let key = self.orderedKeys.removeLast()
        let value = self.dictionary.removeValue(forKey: key)!
        return (key, value)
    }

    @discardableResult
    mutating func removeValue(forKey key: Key) -> Value? {
        guard let index = self.orderedKeys.index(of: key) else {
            return nil
        }
        self.orderedKeys.remove(at: index)
        return self.dictionary.removeValue(forKey: key)
    }

    @discardableResult
    mutating func updateValue(_ value: Value, forKey key: Key) -> Value? {
        let oldValue = self.dictionary[key]
        if oldValue == nil {
            self.orderedKeys.append(key)
        }
        self.dictionary[key] = value
        return oldValue
    }
}

// MARK: ExpressibleByDictionaryLiteral

extension OrderedDictionary: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (Key, Value)...) {
        for (key, value) in elements {
            self[key] = value
        }
    }
}

// MARK: Sequence

extension OrderedDictionary: Sequence {
    typealias Iterator = AnyIterator<Element>

    func makeIterator() -> Iterator {
        var next = 0
        return AnyIterator {
            if next >= self.orderedKeys.count {
                return nil
            }
            let key = self.orderedKeys[next]
            next += 1
            return (key, self.dictionary[key]!)
        }
    }
}

// MARK: MutableCollection

extension OrderedDictionary: MutableCollection {
    typealias Index = Int
    typealias SubSlice = ArraySlice<Element>

    var startIndex: Index {
        return 0
    }

    var endIndex: Index {
        return self.count
    }

    subscript(position: Index) -> Element {
        get {
            let key = self.orderedKeys[position]
            return (key, self.dictionary[key]!)
        }
        set {
            self.remove(at: position)
            self.insert(newValue, at: position)
        }
    }

    subscript(range: Range<Index>) -> SubSlice {
        get {
            let items = Array(self.orderedKeys[range].map { Element($0, self.dictionary[$0]!) })
            return SubSlice(items)
        }
        set {
            self.replaceSubrange(range, with: newValue)
        }
    }

    public func index(after i: Index) -> Index {
        return i.advanced(by: 1)
    }
}

// MARK: RangeReplaceableCollection

extension OrderedDictionary: RangeReplaceableCollection {
    mutating func append(_ newElement: Element) {
        self.insert(newElement, at: self.endIndex)
    }

    mutating func extend<S: Sequence>(_ newElements: S) where S.Iterator.Element == Element {
        for newElement in newElements {
            self.append(newElement)
        }
    }

    mutating func insert(_ newElement: Element, at i: Index) {
        self.splice([newElement], atIndex: i)
    }

    mutating func removeAll(_ keepCapacity: Bool = false) {
        self.dictionary.removeAll(keepingCapacity: keepCapacity)
        self.orderedKeys.removeAll(keepingCapacity: keepCapacity)
    }

    @discardableResult
    mutating func remove(at index: Index) -> Element {
        let key = self.orderedKeys.remove(at: index)
        let value = self.dictionary.removeValue(forKey: key)!
        return (key, value)
    }

    mutating func removeSubrange(_ subRange: Range<Index>) {
        let keys = self.orderedKeys[subRange]
        self.orderedKeys.removeSubrange(subRange)
        for key in keys {
            self.dictionary.removeValue(forKey: key)
        }
    }

    mutating func replaceSubrange<C: Collection>(_ subRange: Range<Index>, with newElements: C) where C.Iterator.Element == Element {
        self.removeSubrange(subRange)
        self.splice(newElements, atIndex: subRange.lowerBound)
    }

    mutating func reserveCapacity(minimumCapacity: Int) {
        self.orderedKeys.reserveCapacity(minimumCapacity)
    }

    mutating func splice<C: Collection>(_ newElements: C, atIndex i: Index) where C.Iterator.Element == Element {
        // TODO: Optimize.
        var index = i
        for element in newElements {
            if let _ = self.dictionary.updateValue(element.value, forKey: element.key) {
                // The key being added already existed, so remove it from its current position.
                let existingIndex = self.orderedKeys.index(of: element.key)!
                self.orderedKeys.remove(at: existingIndex)
                if existingIndex < i {
                    index -= 1
                }
            }
            self.orderedKeys.insert(element.key, at: index)
            index += 1
        }
    }
}

// MARK: Diff method.

extension OrderedDictionary {
    typealias IndexList = [Index]
    typealias MoveList = [(from: Index, to: Index)]
    typealias Difference = (inserted: IndexList, deleted: IndexList, moved: MoveList)

    func diff(_ to: OrderedDictionary) -> Difference {
        // Collect the diff in a tuple.
        var diff: Difference = (IndexList(), IndexList(), MoveList())
        // First, determine what moved.
        for (index, element) in to.enumerated() {
            if let fromIndex = self.keys.index(of: element.key) {
                if index == fromIndex {
                    // Ignore indexes that didn't move.
                    continue
                }
                // The key is no longer in the same place.
                let move = (from: fromIndex, to: index)
                diff.moved.append(move)
            }
        }
        // Calculate deleted keys and keep the other ones for the next step.
        for (index, key) in self.keys.enumerated() {
            if to[key] == nil {
                diff.deleted.append(index)
            }
        }
        // Find inserted keys.
        for (index, element) in to.enumerated() {
            if !self.keys.contains(element.key) {
                // The key is new (not in the current dict).
                diff.inserted.append(index)
            }
        }
        return diff
    }
}
