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
/// **V1 is still being written, and that is the honest description** (#343,
/// 2026-08-28). This used to say a shipped version is never edited. That is the
/// right rule for a shipped app and the wrong one for this one: there is no
/// public release, every store in the world is a TestFlight build's on Georg's
/// own phone, and its contents are disposable until launch. A rule that forbids
/// the ordinary pre-1.0 act of adding a column buys a guarantee nobody needs,
/// paid for in a duplicated copy of every model type per version.
///
/// So the schema **evolves in place until the App Store build**, which is what
/// Apple's own guidance describes: `VersionedSchema` exists for changes that
/// reach a store you do not control, and additive-with-a-default columns are
/// exactly what lightweight migration is for. Every stored-shape change this
/// project has made so far already worked that way.
///
/// **Versioning starts being real at launch.** At that point V1 freezes for
/// good, and freezing it properly means the Apple shape: the model types are
/// *copied into* the version enum — `GlowSchemaV1.Habit` — so the declaration
/// stops moving with today's source, and the live types become V2's with a
/// `MigrationStage` between them. `models` listing `Habit.self` is what makes
/// the current V1 a description of the present rather than a snapshot of the
/// past, and that is fine right up until someone else's store depends on it.
///
/// **The guardrail did not go, it changed shape.** `SchemaContractTests` still
/// holds the code to a written-out list of every attribute and relationship, so
/// a stored-shape change still fails loudly and still has to be answered in the
/// same diff. What it means today is "say so deliberately"; what it will mean
/// after launch is "add a version".
enum GlowSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Habit.self, Completion.self]
    }
}

/// The one migration plan both containers open through.
///
/// **The upgrade floor is TestFlight builds only, and that is documented
/// rather than papered over** — the same fact that lets V1 keep moving until
/// launch, above. No public release of Glow exists; every store
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
