import FileAccess
import Foundation

public enum FileSortOrder: String, CaseIterable, Equatable, Sendable {
    case nameAscending
    case nameDescending
    case kindThenName
    case modifiedNewest
    case modifiedOldest
    case sizeLargest
    case sizeSmallest
    case createdNewest
    case createdOldest
    case availabilityThenName

    public func sorted(_ items: [FileItem]) -> [FileItem] {
        items.sorted { lhs, rhs in
            switch self {
            case .nameAscending:
                return compareNames(lhs, rhs) == .orderedAscending
            case .nameDescending:
                return compareNames(lhs, rhs) == .orderedDescending
            case .kindThenName:
                let lhsRank = kindRank(lhs.kind)
                let rhsRank = kindRank(rhs.kind)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return compareNames(lhs, rhs) == .orderedAscending
            case .modifiedNewest:
                return compareDates(
                    lhs.contentModificationDate,
                    rhs.contentModificationDate,
                    newestFirst: true,
                    lhs: lhs,
                    rhs: rhs
                )
            case .modifiedOldest:
                return compareDates(
                    lhs.contentModificationDate,
                    rhs.contentModificationDate,
                    newestFirst: false,
                    lhs: lhs,
                    rhs: rhs
                )
            case .sizeLargest:
                return compareSizes(lhs, rhs, largestFirst: true)
            case .sizeSmallest:
                return compareSizes(lhs, rhs, largestFirst: false)
            case .createdNewest:
                return compareDates(
                    lhs.creationDate,
                    rhs.creationDate,
                    newestFirst: true,
                    lhs: lhs,
                    rhs: rhs
                )
            case .createdOldest:
                return compareDates(
                    lhs.creationDate,
                    rhs.creationDate,
                    newestFirst: false,
                    lhs: lhs,
                    rhs: rhs
                )
            case .availabilityThenName:
                if lhs.localAvailability != rhs.localAvailability {
                    return availabilityRank(lhs.localAvailability) < availabilityRank(rhs.localAvailability)
                }
                return compareNames(lhs, rhs) == .orderedAscending
            }
        }
    }

    private func compareNames(_ lhs: FileItem, _ rhs: FileItem) -> ComparisonResult {
        lhs.name.localizedStandardCompare(rhs.name)
    }

    private func kindRank(_ kind: FileItem.Kind) -> Int {
        switch kind {
        case .directory:
            return 0
        case .file:
            return 1
        case .symbolicLink:
            return 2
        case .other:
            return 3
        }
    }

    private func compareDates(
        _ lhsDate: Date?,
        _ rhsDate: Date?,
        newestFirst: Bool,
        lhs: FileItem,
        rhs: FileItem
    ) -> Bool {
        switch (lhsDate, rhsDate) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return newestFirst ? lhsDate > rhsDate : lhsDate < rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return compareNames(lhs, rhs) == .orderedAscending
        }
    }

    private func compareSizes(_ lhs: FileItem, _ rhs: FileItem, largestFirst: Bool) -> Bool {
        switch (lhs.byteSize, rhs.byteSize) {
        case let (lhsSize?, rhsSize?) where lhsSize != rhsSize:
            return largestFirst ? lhsSize > rhsSize : lhsSize < rhsSize
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return compareNames(lhs, rhs) == .orderedAscending
        }
    }

    private func availabilityRank(_ availability: FileItem.LocalAvailability) -> Int {
        switch availability {
        case .local:
            return 0
        case .downloadRequired:
            return 1
        case .unknown:
            return 2
        }
    }
}
