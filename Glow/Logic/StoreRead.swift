import Foundation

/// What a read of the store produced: a value, nothing, or no answer at all.
///
/// **Empty and unavailable are different facts, and collapsing them was #282.**
/// A widget whose container failed to open rendered the same "No habits yet"
/// as a fresh install, because the read path encoded both outcomes as an empty
/// array — a temporary database failure drawn as the deletion of every habit.
/// The error was erased before the UI could distinguish, so no view code could
/// fix it; the state has to survive in the type.
///
/// Three cases rather than an `Optional` or a `Result`, because the three are
/// what a surface renders: `loaded` draws the value, `empty` draws the honest
/// "nothing here yet", and `unavailable` draws a recovery path. What it does
/// *not* carry is the underlying error — that is logged where it happened,
/// privacy-qualified, and a rendered surface never shows framework error text,
/// habit names or paths (#282's own rule).
///
/// Pure and generic, per the `WeekGrid` pattern: the store boundary produces
/// one of these, everything downstream only switches on it.
enum StoreRead<Value> {
    /// The read succeeded and found this.
    case loaded(Value)
    /// The read succeeded and found nothing. The one case that may honestly
    /// say "No habits yet".
    case empty
    /// The container did not open or the fetch failed. Never rendered as
    /// emptiness; the surface offers the way to the app's recovery screen.
    case unavailable

    /// The value, when there is one.
    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

extension StoreRead where Value: Collection {
    /// The boundary's one mapping, so no call site can invent its own:
    /// a failed read is `nil` and becomes `unavailable`; a successful read of
    /// nothing is an empty collection and becomes `empty`.
    init(read value: Value?) {
        guard let value else {
            self = .unavailable
            return
        }
        self = value.isEmpty ? .empty : .loaded(value)
    }
}

extension StoreRead: Equatable where Value: Equatable {}
extension StoreRead: Sendable where Value: Sendable {}
