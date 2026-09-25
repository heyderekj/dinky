import Foundation

/// The preset selected in the main window, if it should drive a given file. Resolved when a file is
/// added so later edits to the preset apply, instead of the copy taken when it was selected.
public enum ActivePresetResolver {
    public static func presetID(
        activePresetID: String,
        savedPresets: [CompressionPreset],
        mediaType: MediaType?
    ) -> UUID? {
        guard let id = UUID(uuidString: activePresetID),
              let media = mediaType,
              let preset = savedPresets.first(where: { $0.id == id }),
              preset.applies(to: media)
        else { return nil }
        return id
    }
}
