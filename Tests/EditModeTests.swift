import Foundation
import Testing
@testable import Glow

/// #164: which views may read `\.editMode`, and which must own it instead.
///
/// The distinction is structural, not stylistic. `EditButton` toggles the
/// binding it finds in *its* environment — the one the `NavigationStack` around
/// it provides — so a view that reads `@Environment(\.editMode)` sees the live
/// value exactly when it is a descendant of that stack. A view whose own `body`
/// builds the stack is not: the value it would read is its parent's, and it
/// reads `.inactive` forever while the button animates to Done (that is the
/// trap in CLAUDE.md, and it cost a real bug — on the Today screen, which is no
/// longer here to demonstrate it, #209). `HabitRowView` and
/// `WeekdayHeader` are descendants, so they read it directly and #164's fade
/// rests on that.
///
/// Both halves are claims about *where a declaration sits*, which no test of a
/// value can make: a wrongly-placed read compiles, runs, and is simply always
/// false. The scan is the assertion, in the same spirit as
/// `WidgetTraceRedactionTests`.
@Suite("Edit mode")
struct EditModeTests {
    /// This repository's app-side Swift sources, found from the test file's own
    /// path — the same walk `ReduceMotionTests` makes, and for the same reason:
    /// the claim is about every file, not about the three that exist today.
    private var sourceFiles: [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // the checkout
        let targets = ["Glow", "GlowWidget"].map {
            root.appendingPathComponent($0, isDirectory: true)
        }
        return targets.flatMap { directory -> [URL] in
            let walker = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil
            )
            let all = (walker?.allObjects as? [URL]) ?? []
            return all.filter { $0.pathExtension == "swift" }
        }
    }

    /// One file's `struct`s, as text, so a declaration can be attributed to the
    /// type it belongs to. Split on the keyword at column zero, which is how
    /// every type in this codebase is written; a nested type would ride along
    /// with its parent, which is the answer this scan wants anyway.
    private func types(in text: String) -> [String] {
        text.components(separatedBy: "\nstruct ")
    }

    private let environmentRead = "@Environment(\\.editMode)"

    /// Whether this text *declares* the read, rather than talking about it.
    ///
    /// A doc comment can quote the spelling in the course of explaining why a
    /// view cannot use it — one did, and a plain substring search called that a
    /// violation. The scan has to see code, so it looks for the property
    /// wrapper at the head of a line.
    private func declaresEnvironmentRead(_ text: String) -> Bool {
        text.split(separator: "\n").contains { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix(environmentRead)
        }
    }

    @Test("The view that builds the stack never reads the environment's editMode")
    func theStackBuilderOwnsItInstead() throws {
        let files = sourceFiles
        #expect(!files.isEmpty, "no sources found; the scan would pass vacuously")

        var offenders: [String] = []
        var stacks = 0
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for type in types(in: text) where type.contains("NavigationStack {") {
                stacks += 1
                if declaresEnvironmentRead(type) {
                    offenders.append(file.lastPathComponent)
                }
            }
        }

        #expect(stacks >= 2, "found \(stacks) view(s) building a NavigationStack")
        #expect(
            offenders.isEmpty,
            "reads \(environmentRead) in the view that builds the stack: \(offenders)"
        )
    }

    @Test("Every surface the week grid fades reads editMode itself")
    func theGridsSurfacesReadItDirectly() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Glow/Views", isDirectory: true)

        // The row carries the track and the rest-day cut; the header carries
        // the letters over the columns. They fade together, on one timing, so
        // they have to agree about when — which means each reads the value
        // rather than being told.
        for name in ["HabitRowView.swift", "WeeklyGridView.swift"] {
            let text = try String(
                contentsOf: root.appendingPathComponent(name), encoding: .utf8
            )
            #expect(
                declaresEnvironmentRead(text),
                "\(name) no longer reads \(environmentRead)"
            )
        }
    }

    /// #320: the week grid's edit control is the ellipsis menu's own `Button`,
    /// toggling the `EditMode` state the view owns — not `EditButton`, which
    /// has no menu-item form and writes to whatever environment it happens to
    /// sit in. Reintroducing it would put a second writer beside the owned
    /// state. Comment lines are excluded because the code explains this
    /// decision by naming the type it declined.
    @Test("The week grid never constructs EditButton")
    func theGridDoesNotUseEditButton() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Glow/Views/WeeklyGridView.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        let constructions = text.split(separator: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("//") && trimmed.contains("EditButton(")
        }
        #expect(
            constructions.isEmpty,
            "WeeklyGridView constructs EditButton again: \(constructions)"
        )
    }
}
