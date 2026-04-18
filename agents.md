# Agent notes — Dinky (macOS)

Use this alongside `CLAUDE.md`. It records **product and UI conventions** so changes stay consistent.

## Apple design language (macOS Settings–style UI)

- **Segmented controls** (`Picker` + `.pickerStyle(.segmented)`): Use for **2–5 mutually exclusive panes** in a single settings surface (e.g. Image / Video / PDF under Presets). This matches System Settings patterns and avoids long vertical scrolling for parallel option groups.
- **Top-level window tabs** (`TabView` with tab items): Reserve for **major areas** of the settings window (General, Output, Watch, Presets)—not for small sub-panes inside a tab.
- **Grouped `Form`**: Use section **headers** to name groups; use **footers** sparingly for secondary explanation (progressive disclosure). Prefer concise captions over long instructional blocks.
- **Accessibility**: If `.labelsHidden()` is used on a control for layout, set `.accessibilityLabel` (and related inputs when needed) so VoiceOver still describes the control.
- **Hierarchy**: Place the control that **changes scope** (segmented picker) **above** the content it affects, with a clear section header (e.g. “Media”).
- **Cross-cutting settings**: If an option affects multiple panes (e.g. Smart quality and PDF/video tiers), keep it in a **dedicated section above** the segmented control so it stays visible when switching panes.

## App constraints

- See `CLAUDE.md` for bundle size and dependency rules.
