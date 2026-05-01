import DinkyCoreImage
import SwiftUI

extension OriginalsAction {
    var displayName: String {
        switch self {
        case .keep: return "Stay where they are"
        case .trash: return "Move to Trash"
        case .backup: return "Move to Backup folder"
        }
    }
}

extension CollisionNamingStyle {
    var displayName: String {
        switch self {
        case .finderDuplicate:
            return String(localized: "“Copy”, “Copy 2”, …", comment: "Collision naming style: Finder duplicate.")
        case .finderNumbered:
            return String(localized: "“(1)”, “(2)”, …", comment: "Collision naming style: numbered parentheses.")
        case .custom:
            return String(localized: "Add my own text", comment: "Collision naming style: user-defined extra text in the filename.")
        }
    }
}
