import SwiftUI
import AppKit

// MARK: - Window scene

/// Opens via the Help menu (⌘?) and from the in-window button on errors.
/// Renders `Help.md` from the bundle. Keeping content in markdown means we can
/// edit the help copy without touching SwiftUI code, and never ship a `.help`
/// bundle (which would add weight and indexing overhead — see CLAUDE.md).
struct HelpWindow: View {
    @State private var sections: [HelpSection] = HelpDocument.load()
    @State private var selection: HelpSection.ID?

    var body: some View {
        NavigationSplitView {
            List(sections, selection: $selection) { section in
                Text(section.title).tag(section.id as HelpSection.ID?)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            ScrollView {
                if let id = selection ?? sections.first?.id,
                   let section = sections.first(where: { $0.id == id }) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(section.title)
                            .font(.system(size: 26, weight: .semibold))
                            .padding(.bottom, 2)
                        ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                            HelpBlockView(block: block)
                        }
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(.background)
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            if selection == nil { selection = sections.first?.id }
        }
    }
}

// MARK: - Block renderer

private struct HelpBlockView: View {
    let block: HelpBlock

    var body: some View {
        switch block {
        case .heading(let text):
            Text(text)
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 6)

        case .paragraph(let text):
            Text(LocalizedStringKey(text))
                .font(.system(size: 13))
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(LocalizedStringKey(item))
                            .font(.system(size: 13))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .ordered(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(idx + 1).").foregroundStyle(.secondary).monospacedDigit()
                        Text(LocalizedStringKey(item))
                            .font(.system(size: 13))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 3)
                Text(LocalizedStringKey(text))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

        case .table(let headers, let rows):
            VStack(alignment: .leading, spacing: 0) {
                tableRow(headers, isHeader: true)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Divider()
                    tableRow(row, isHeader: false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )

        case .rule:
            Divider().padding(.vertical, 4)
        }
    }

    private func tableRow(_ cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(LocalizedStringKey(cell))
                    .font(.system(size: 12, weight: isHeader ? .semibold : .regular))
                    .foregroundStyle(isHeader ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Document model

struct HelpSection: Identifiable, Hashable {
    let id: String
    let title: String
    let blocks: [HelpBlock]
}

enum HelpBlock: Hashable {
    case heading(String)
    case paragraph(String)
    case bullets([String])
    case ordered([String])
    case quote(String)
    case table(headers: [String], rows: [[String]])
    case rule
}

/// Parses `Help.md` into sections (split on `## ` headings) and typed blocks.
/// Inline markdown (bold, italic, links, code) is left as-is and rendered later
/// via `Text(LocalizedStringKey:)`, which understands those tokens natively.
enum HelpDocument {
    static func load() -> [HelpSection] {
        guard let url = Bundle.main.url(forResource: "Help", withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return [HelpSection(
                id: "missing",
                title: "Help",
                blocks: [.paragraph("Help content couldn't be loaded.")]
            )]
        }
        return parse(raw)
    }

    static func parse(_ markdown: String) -> [HelpSection] {
        var sections: [HelpSection] = []
        var currentTitle: String? = nil
        var currentLines: [String] = []

        // Skip the leading H1 (used as the document title) and treat each
        // H2 as a navigable section. Everything before the first H2 becomes
        // the introductory "Welcome" section using the H1's title.
        var introTitle = "Welcome"
        var introCaptured = false

        func flush() {
            let title = currentTitle ?? (introCaptured ? "Section" : introTitle)
            let blocks = parseBlocks(currentLines)
            // Drop empty sections (e.g., a trailing `---`)
            if !blocks.isEmpty {
                sections.append(HelpSection(id: title, title: title, blocks: blocks))
            }
            currentLines.removeAll()
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine
            if line.hasPrefix("# ") && !introCaptured {
                introTitle = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("## ") {
                if !introCaptured {
                    flush()
                    introCaptured = true
                } else {
                    flush()
                }
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }
            currentLines.append(line)
        }
        flush()
        return sections
    }

    private static func parseBlocks(_ lines: [String]) -> [HelpBlock] {
        var blocks: [HelpBlock] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            if trimmed == "---" {
                blocks.append(.rule)
                i += 1
                continue
            }

            if trimmed.hasPrefix("### ") {
                blocks.append(.heading(String(trimmed.dropFirst(4))))
                i += 1
                continue
            }

            if trimmed.hasPrefix("> ") {
                var quoteLines: [String] = [String(trimmed.dropFirst(2))]
                i += 1
                while i < lines.count {
                    let next = lines[i].trimmingCharacters(in: .whitespaces)
                    if next.hasPrefix("> ") {
                        quoteLines.append(String(next.dropFirst(2)))
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.quote(quoteLines.joined(separator: " ")))
                continue
            }

            if trimmed.hasPrefix("- ") {
                var items: [String] = []
                while i < lines.count {
                    let cur = lines[i].trimmingCharacters(in: .whitespaces)
                    if cur.hasPrefix("- ") {
                        items.append(String(cur.dropFirst(2)))
                        i += 1
                    } else if cur.isEmpty {
                        break
                    } else if !items.isEmpty && !cur.hasPrefix("- ") {
                        // Continuation line (rare in our help) — append to last item.
                        items[items.count - 1] += " " + cur
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bullets(items))
                continue
            }

            if let first = trimmed.first, first.isNumber, isOrderedListItem(trimmed) {
                var items: [String] = []
                while i < lines.count {
                    let cur = lines[i].trimmingCharacters(in: .whitespaces)
                    if isOrderedListItem(cur) {
                        items.append(stripOrderedPrefix(cur))
                        i += 1
                    } else if cur.isEmpty {
                        break
                    } else {
                        items[items.count - 1] += " " + cur
                        i += 1
                    }
                }
                blocks.append(.ordered(items))
                continue
            }

            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                var rows: [[String]] = []
                while i < lines.count {
                    let cur = lines[i].trimmingCharacters(in: .whitespaces)
                    if cur.hasPrefix("|") && cur.hasSuffix("|") {
                        rows.append(parseTableRow(cur))
                        i += 1
                    } else {
                        break
                    }
                }
                // Drop the separator row (e.g. `| --- | --- |`)
                let cleaned = rows.filter { row in
                    !row.allSatisfy { cell in
                        cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " } && !cell.isEmpty
                    }
                }
                if let header = cleaned.first {
                    blocks.append(.table(headers: header, rows: Array(cleaned.dropFirst())))
                }
                continue
            }

            // Paragraph — accumulate until blank line or new block marker.
            var paragraph: [String] = [trimmed]
            i += 1
            while i < lines.count {
                let next = lines[i].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || next.hasPrefix("- ") || next.hasPrefix("> ")
                    || next.hasPrefix("### ") || next == "---" || next.hasPrefix("|") {
                    break
                }
                paragraph.append(next)
                i += 1
            }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
        }
        return blocks
    }

    private static func isOrderedListItem(_ line: String) -> Bool {
        var sawDigit = false
        for ch in line {
            if ch.isNumber { sawDigit = true; continue }
            if ch == "." && sawDigit { return true }
            return false
        }
        return false
    }

    private static func stripOrderedPrefix(_ line: String) -> String {
        guard let dot = line.firstIndex(of: ".") else { return line }
        let after = line.index(after: dot)
        return String(line[after...]).trimmingCharacters(in: .whitespaces)
    }

    private static func parseTableRow(_ line: String) -> [String] {
        line.dropFirst().dropLast()
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
