import Foundation
import SwiftData

/// Versioned SwiftData schema for Tideline v1.x.
///
/// **Why this exists** (audit fix): the original `ModelContainer(for:)` call
/// shipped without a `VersionedSchema` or `SchemaMigrationPlan`. That meant
/// any post-launch addition / rename / relationship change to a `@Model`
/// class would corrupt existing user installs — SwiftData has no recovery
/// path for an unmanaged schema diff. Scaffolding the V1 schema NOW (before
/// first ship) means the first migration the app needs can introduce V2 +
/// a real migration stage without a destructive rebuild.
///
/// **What this does today**: declares the current model set as the single
/// schema version, wired into `AppContainer` via `ModelContainer(for:_,
/// migrationPlan:)`. No data is migrated yet — there's nothing to migrate
/// from. The infrastructure exists so future schema work has a deterministic
/// migration target.
///
/// **Adding V2 later** (worked example):
///   1. Create `SchemaV2` enum mirroring this one with the new field shapes.
///   2. Add a `MigrationStage.custom` or `.lightweight(...)` to
///      `TidelineMigrationPlan.stages` describing the V1→V2 transition.
///   3. Update `AppContainer`'s schema arg to `SchemaV2.versionedSchema`.
///   4. Keep this file unchanged — V1 must remain frozen as the migration
///      source for any user still on a 1.x install.
public enum SchemaV1: VersionedSchema {
    // `static let` (not `var`) so Swift 6 strict concurrency doesn't flag
    // this as nonisolated mutable global state. The `VersionedSchema`
    // protocol declares the requirement as `static var ... { get }`; a
    // `static let` satisfies a get-only static var requirement.
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Cycle.self, DayEntry.self, CycleEvent.self]
    }
}

/// Migration plan. Single stage today (V1 is the initial schema), but the
/// type exists so the plumbing is in place for the first real V1→V2
/// transition. iOS picks `lightweight` vs `custom` per stage; lightweight
/// handles additive field changes automatically.
public enum TidelineMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        // Empty array == no migrations needed yet. SwiftData treats this as
        // "the current schema is the only one I've ever known." When V2
        // ships, this becomes `[.lightweight(fromVersion: SchemaV1.self,
        // toVersion: SchemaV2.self)]` or a custom stage with willMigrate /
        // didMigrate closures.
        []
    }
}
