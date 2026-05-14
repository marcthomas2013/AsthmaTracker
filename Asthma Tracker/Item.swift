import Foundation
import SwiftData

@Model
final class InhalerEvent {
    var takenAt: Date = Date.now
    var inhalerTypeRaw: String = InhalerType.preventative.rawValue
    var reason: String = "Unspecified"
    var puffCount: Int = 1
    var notes: String = ""
    var isSyncedToHealthKit: Bool = false

    init(
        takenAt: Date,
        inhalerType: InhalerType,
        reason: String = "Unspecified",
        puffCount: Int = 1,
        notes: String = "",
        isSyncedToHealthKit: Bool = false
    ) {
        self.takenAt = takenAt
        self.inhalerTypeRaw = inhalerType.rawValue
        self.reason = reason
        self.puffCount = puffCount
        self.notes = notes
        self.isSyncedToHealthKit = isSyncedToHealthKit
    }
}

@Model
final class InhalerReasonOption {
    var inhalerTypeRaw: String = InhalerType.preventative.rawValue
    var reason: String = ""
    var createdAt: Date = Date.now

    init(inhalerType: InhalerType, reason: String, createdAt: Date = .now) {
        self.inhalerTypeRaw = inhalerType.rawValue
        self.reason = reason
        self.createdAt = createdAt
    }
}

@Model
final class TrackedInhaler {
    var inhalerTypeRaw: String = InhalerType.preventative.rawValue
    var createdAt: Date = Date.now
    var defaultReasonsSeeded: Bool = false

    init(inhalerType: InhalerType, createdAt: Date = Date.now, defaultReasonsSeeded: Bool = false) {
        self.inhalerTypeRaw = inhalerType.rawValue
        self.createdAt = createdAt
        self.defaultReasonsSeeded = defaultReasonsSeeded
    }
}

enum InhalerType: String, Codable, CaseIterable, Identifiable {
    case preventative = "Preventative"
    case reliever = "Reliever"
    case combined = "Combined"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .preventative:
            return "lungs.fill"
        case .reliever:
            return "bolt.heart.fill"
        case .combined:
            return "cross.case.fill"
        }
    }

    var defaultReasons: [String] {
        switch self {
        case .preventative:
            return ["Scheduled daily dose", "Before expected triggers", "Following care plan"]
        case .reliever:
            return ["Shortness of breath", "Wheezing", "Night-time symptoms", "Before exercise"]
        case .combined:
            return ["Scheduled maintenance dose", "Symptoms flare-up", "Before known trigger exposure"]
        }
    }
}
