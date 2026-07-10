import Foundation
import Observation

@MainActor
@Observable
final class ZonesStore {
    private(set) var zones: [String]

    private let zonesKey = AppStorageKey.zones.rawValue
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.zones = defaults.stringArray(forKey: zonesKey) ?? []
    }

    func add(_ name: String) {
        guard let normalized = ZoneCatalog.normalized(name),
              !ZoneCatalog.isDuplicate(normalized, in: zones) else { return }
        zones.append(normalized)
        persist()
    }

    func remove(_ zone: String) {
        guard let index = zones.firstIndex(of: zone) else { return }
        zones.remove(at: index)
        persist()
    }

    func rename(_ zone: String, to newName: String) {
        guard let index = zones.firstIndex(of: zone),
              let normalized = ZoneCatalog.normalized(newName) else { return }
        guard normalized == zone || !ZoneCatalog.isDuplicate(normalized, in: zones) else { return }
        zones[index] = normalized
        persist()
    }

    func move(zone: String, before target: String) {
        guard zone != target,
              let srcIndex = zones.firstIndex(of: zone) else { return }
        zones.remove(at: srcIndex)
        guard let dstIndex = zones.firstIndex(of: target) else {
            zones.insert(zone, at: srcIndex)
            return
        }
        zones.insert(zone, at: dstIndex)
        persist()
    }

    func moveToEnd(zone: String) {
        guard let srcIndex = zones.firstIndex(of: zone) else { return }
        zones.remove(at: srcIndex)
        zones.append(zone)
        persist()
    }

    /// Applies `ZoneCatalog.reconciled` and persists only when it actually
    /// changed, to avoid write-churn on every load.
    func reconcile(withHostZones hostZones: [String]) {
        let updated = ZoneCatalog.reconciled(declared: zones, hostZones: hostZones)
        guard updated != zones else { return }
        zones = updated
        persist()
    }

    private func persist() {
        defaults.set(zones, forKey: zonesKey)
    }
}
