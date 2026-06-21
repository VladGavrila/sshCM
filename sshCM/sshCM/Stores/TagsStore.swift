import Foundation
import Observation

@MainActor
@Observable
final class TagsStore {
    private(set) var tags: [String: HostTag]
    private(set) var tagOrder: [HostTag]
    private(set) var tagNames: [HostTag: String]

    private let tagsKey  = AppStorageKey.hostTags.rawValue
    private let orderKey = AppStorageKey.hostTagOrder.rawValue
    private let namesKey = AppStorageKey.hostTagNames.rawValue
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        var parsed: [String: HostTag] = [:]
        if let raw = defaults.dictionary(forKey: tagsKey) as? [String: String] {
            for (alias, value) in raw {
                if let tag = HostTag(rawValue: value) {
                    parsed[alias] = tag
                }
            }
        }
        self.tags = parsed

        if let stored = defaults.stringArray(forKey: orderKey) {
            var seen = Set<HostTag>()
            var order: [HostTag] = []
            for raw in stored {
                if let tag = HostTag(rawValue: raw), seen.insert(tag).inserted {
                    order.append(tag)
                }
            }
            for tag in HostTag.defaultOrder where !seen.contains(tag) {
                order.append(tag)
            }
            self.tagOrder = order
        } else {
            self.tagOrder = HostTag.defaultOrder
        }

        var names: [HostTag: String] = [:]
        if let rawNames = defaults.dictionary(forKey: namesKey) as? [String: String] {
            for (key, value) in rawNames {
                if let tag = HostTag(rawValue: key) {
                    names[tag] = value
                }
            }
        }
        self.tagNames = names
    }

    func rank(for tag: HostTag) -> Int {
        tagOrder.firstIndex(of: tag) ?? tagOrder.count
    }

    func move(tag: HostTag, by offset: Int) {
        guard let index = tagOrder.firstIndex(of: tag) else { return }
        let target = index + offset
        guard tagOrder.indices.contains(target) else { return }
        tagOrder.swapAt(index, target)
        persistOrder()
    }

    func move(tag: HostTag, before target: HostTag) {
        guard tag != target,
              let srcIndex = tagOrder.firstIndex(of: tag) else { return }
        tagOrder.remove(at: srcIndex)
        guard let dstIndex = tagOrder.firstIndex(of: target) else {
            tagOrder.insert(tag, at: srcIndex)
            return
        }
        tagOrder.insert(tag, at: dstIndex)
        persistOrder()
    }

    func moveToEnd(tag: HostTag) {
        guard let srcIndex = tagOrder.firstIndex(of: tag) else { return }
        tagOrder.remove(at: srcIndex)
        tagOrder.append(tag)
        persistOrder()
    }

    func resetOrder() {
        tagOrder = HostTag.defaultOrder
        persistOrder()
    }

    func displayName(for tag: HostTag) -> String {
        if let custom = tagNames[tag],
           !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        return tag.displayName
    }

    func customName(for tag: HostTag) -> String? {
        tagNames[tag]
    }

    func rename(tag: HostTag, to name: String) {
        if name.isEmpty {
            tagNames.removeValue(forKey: tag)
        } else {
            tagNames[tag] = name
        }
        persistNames()
    }

    func tag(for alias: String) -> HostTag? {
        guard !alias.isEmpty else { return nil }
        return tags[alias]
    }

    func set(_ tag: HostTag?, for alias: String) {
        guard !alias.isEmpty else { return }
        if let tag {
            tags[alias] = tag
        } else {
            tags.removeValue(forKey: alias)
        }
        persist()
    }

    func remove(alias: String) {
        guard !alias.isEmpty, tags[alias] != nil else { return }
        tags.removeValue(forKey: alias)
        persist()
    }

    private func persist() {
        let raw = tags.mapValues { $0.rawValue }
        defaults.set(raw, forKey: tagsKey)
    }

    private func persistOrder() {
        defaults.set(tagOrder.map(\.rawValue), forKey: orderKey)
    }

    private func persistNames() {
        let raw = Dictionary(uniqueKeysWithValues: tagNames.map { ($0.key.rawValue, $0.value) })
        defaults.set(raw, forKey: namesKey)
    }
}
