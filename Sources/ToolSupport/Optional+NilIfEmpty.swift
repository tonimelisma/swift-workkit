import Foundation

// REQ: ROADMAP item 1.a — Shared text helpers used by the ToolKit* domain
// modules (PIM, Places, Notifications, Photos). Lives outside ToolVocabulary
// because those modules need only this 7-line convention, and
// "ToolVocabulary is the only shared language between Recorder and ToolKit"
// (ToolAnnotations.swift:1-5) shouldn't erode for a string trimmer. No
// products — internal target, imported by name.

extension Optional where Wrapped == String {
    /// The tools' empty-is-absent convention: `nil` and `""` and whitespace-only
    /// all become `nil`, so a model that passes an empty optional doesn't
    /// accidentally set a field to blank. Distinguished from the patch-overlay
    /// helper (see e.g. UpdateContactTool) that uses this to mean *preserve
    /// current* — that layer adds the nil-preserves/empty-clears distinction
    /// on top.
    public var nilIfEmpty: String? {
        guard let value = self else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension String {
    /// Non-optional twin: used by the required-id guards, where the value is
    /// never optional but still needs whitespace-is-absent semantics.
    public var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}