import Foundation
import SwiftData

/// The stored schema, as an immutable version rather than an inference (#283).
///
/// Production used to open a plain `Schema([Habit.self, Completion.self])`
/// and leave compatibility to what SwiftData infers from today's source. That
/// worked because every shipped change so far has been additive — defaulted
/// columns, an optional relationship — but it versioned nothing: a future
/// model edit would pass every current test, which all open current-schema
/// stores with current-schema code, and still strand a returning person's
/// store at a shape no declared migration covers.
///
/// **V1 is a snapshot of the shape shipping today**, frozen. It is the same
/// two model types the plain schema listed, so adopting it changes no bytes
/// in any store — the SQLite schema is identical, and `SchemaContractTests`
/// holds this type to the shape it froze. A model edit that changes stored
/// metadata now fails that test, and the answer to the failure is a decision:
/// a `GlowSchemaV2` and a `MigrationStage`, or an explicit choice to reuse V1
/// for a change that provably does not alter the store.
///
/// **A shipped version is never edited.** Once a build carrying V1 is on
/// anyone's phone, this declaration is a compatibility contract with the
/// stores that build wrote; the next shape is a new version in the plan, not
/// a revision here.
enum GlowSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Habit.self, Completion.self]
    }
}

/// The one migration plan both containers open through.
///
/// **The upgrade floor is TestFlight builds only, and that is documented
/// rather than papered over.** No public release of Glow exists; every store
/// in the world was written by a TestFlight build whose stored shape is what
/// V1 freezes — the earlier stored-shape changes (`dayKey`, the per-day
/// residue) were additive-with-default and are read by V1 exactly as the
/// builds that made them wrote them, with the row backfills below handling
/// the contents. Shapes older than that floor are **explicitly unsupported
/// and deliberately not reconstructed**: #283 offered rebuilding historical
/// schemas from tagged commits and checking in store fixtures, and the answer
/// is no — inventing versions for shapes no surviving store can hold would be
/// history nobody can test against honestly. If a pre-floor store ever
/// surfaces, it fails to open, `GlowStore.makeContainer` throws, and the app
/// stops on `StoreUnavailableView` with the store untouched — the same
/// refuse-rather-than-improvise contract the file migration follows. The
/// widget's read-only open fails nil and renders *unavailable*, never "No
/// habits yet" (#282).
///
/// **The order of the three migration layers is fixed, and this plan is the
/// middle one.** First `StoreMigration.run` settles *where* the store file
/// is — staging, validating and promoting whole DB/WAL/SHM sets, never
/// schema-aware beyond opening them. Then the container open runs this plan,
/// which settles *what shape* the rows are in. Last the row backfills —
/// `StoreMigration.stampDayIdentities`, `DailyHabitMigration` — settle row
/// *contents*, and both are defined by what is still unstamped or left over,
/// so neither marks the others complete. A future stage in this plan must
/// keep that position: it may assume the file is in place and must not assume
/// any backfill has run.
///
/// `stages` is empty because one version has no path to migrate along; the
/// plan still runs on every open, which is what makes adding V2's stage a
/// change in data rather than in plumbing.
enum GlowMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [GlowSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
