import Foundation

/// What the Library sidebar currently narrows the list to. The scope always
/// combines (AND) with whatever is typed in the search field.
enum LibraryScope: Hashable {
    case all
    case pinned
    /// Source app, keyed by bundle id (or app name when no bundle id is known).
    case app(String)
    case type(PickerTypeFilter)
    case tag(String)
}

struct LibraryAppEntry: Identifiable, Equatable {
    let key: String
    let name: String
    let bundleID: String?
    let count: Int

    var id: String { key }
}

struct LibraryTagEntry: Identifiable, Equatable {
    let tag: String
    let count: Int

    var id: String { tag }
}

enum LibraryDateGroup: Int, CaseIterable, Comparable, Identifiable {
    case pinned
    case today
    case yesterday
    case lastSevenDays
    case earlier

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .pinned: return "Pinned"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .lastSevenDays: return "Previous 7 Days"
        case .earlier: return "Earlier"
        }
    }

    static func < (lhs: LibraryDateGroup, rhs: LibraryDateGroup) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Date bucket for an unpinned clip. Never returns `.pinned`.
    static func group(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> LibraryDateGroup {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        let startOfToday = calendar.startOfDay(for: now)
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday), date >= weekAgo {
            return .lastSevenDays
        }
        return .earlier
    }
}

struct LibrarySection: Identifiable, Equatable {
    let group: LibraryDateGroup
    let items: [ClipboardHistoryItem]

    var id: Int { group.rawValue }
}

/// Pure filtering, grouping and sidebar-count logic for the Library window.
enum LibraryFilter {
    static func appKey(for item: ClipboardHistoryItem) -> String? {
        if let bundleID = item.sourceAppBundleID, !bundleID.isEmpty { return bundleID }
        if let name = item.sourceAppName, !name.isEmpty { return name }
        return nil
    }

    /// Applies the sidebar scope and the search query. Both must match, so
    /// e.g. scope `.app("Safari")` plus `@Xcode` yields nothing instead of
    /// silently preferring one of them.
    static func apply(_ clips: [ClipboardHistoryItem], scope: LibraryScope, query: String) -> [ClipboardHistoryItem] {
        let search = PickerSearchQuery(query)
        return clips.filter { matches($0, scope: scope, search: search) }
    }

    static func matches(_ item: ClipboardHistoryItem, scope: LibraryScope, search: PickerSearchQuery) -> Bool {
        switch scope {
        case .all:
            break
        case .pinned:
            guard item.isPinned else { return false }
        case .app(let key):
            guard appKey(for: item) == key else { return false }
        case .type(let filter):
            guard filter.matches(item.kind) else { return false }
        case .tag(let tag):
            guard item.tags.contains(tag) else { return false }
        }

        guard search.tags.allSatisfy({ item.tags.contains($0) }) else { return false }
        if let typeFilter = search.typeFilter, !typeFilter.matches(item.kind) { return false }
        guard search.appQueries.allSatisfy({ item.matchesSourceAppQuery($0) }) else { return false }
        guard search.text.isEmpty || item.searchText.localizedCaseInsensitiveContains(search.text) else { return false }
        return true
    }

    /// Groups clips for display: pinned clips first (Quick Slot order), then
    /// newest-first date buckets. Empty groups are omitted.
    static func sections(
        for clips: [ClipboardHistoryItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [LibrarySection] {
        var pinned: [ClipboardHistoryItem] = []
        var buckets: [LibraryDateGroup: [ClipboardHistoryItem]] = [:]

        for clip in clips {
            if clip.isPinned {
                pinned.append(clip)
            } else {
                buckets[LibraryDateGroup.group(for: clip.createdAt, now: now, calendar: calendar), default: []].append(clip)
            }
        }

        var sections: [LibrarySection] = []
        if !pinned.isEmpty {
            sections.append(LibrarySection(group: .pinned, items: pinned.sortedByPinnedOrder()))
        }
        for group in LibraryDateGroup.allCases where group != .pinned {
            if let items = buckets[group], !items.isEmpty {
                sections.append(LibrarySection(group: group, items: items))
            }
        }
        return sections
    }

    static func apps(in clips: [ClipboardHistoryItem]) -> [LibraryAppEntry] {
        var counts: [String: (name: String, bundleID: String?, count: Int)] = [:]
        for clip in clips {
            guard let key = appKey(for: clip) else { continue }
            let name = clip.sourceAppName ?? key
            let existing = counts[key]
            counts[key] = (name, clip.sourceAppBundleID, (existing?.count ?? 0) + 1)
        }
        return counts
            .map { LibraryAppEntry(key: $0.key, name: $0.value.name, bundleID: $0.value.bundleID, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.count > rhs.count
            }
    }

    static func tags(in clips: [ClipboardHistoryItem]) -> [LibraryTagEntry] {
        var counts: [String: Int] = [:]
        for clip in clips {
            for tag in clip.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .map { LibraryTagEntry(tag: $0.key, count: $0.value) }
            .sorted { $0.tag < $1.tag }
    }

    /// Number of clips per concrete type filter (excluding `.all`).
    static func typeCounts(in clips: [ClipboardHistoryItem]) -> [PickerTypeFilter: Int] {
        var counts: [PickerTypeFilter: Int] = [:]
        for filter in PickerTypeFilter.allCases where filter != .all {
            counts[filter] = clips.filter { filter.matches($0.kind) }.count
        }
        return counts
    }
}
