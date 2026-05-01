import DinkyCoreImage
import SwiftUI

/// Localized display names; core format lives in ``DinkyCoreImage``.
extension CompressionFormat {
    var displayName: String {
        switch self {
        case .webp: return S.webp
        case .avif: return S.avif
        case .png:  return S.png
        case .heic: return S.heic
        }
    }
}
