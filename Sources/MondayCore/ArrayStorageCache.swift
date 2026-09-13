struct ArrayStorageCache<Element> {
    private var entries: [Int: [[Element]]] = [:]

    mutating func share(_ values: [Element]) -> [Element] {
        values.withUnsafeBytes { bytes in
            var hasher = Hasher()
            hasher.combine(bytes: bytes)
            let key = hasher.finalize()
            if let existing = entries[key]?.first(where: { $0.withUnsafeBytes { $0.elementsEqual(bytes) } }) { return existing }
            entries[key, default: []].append(values)
            return values
        }
    }
}
