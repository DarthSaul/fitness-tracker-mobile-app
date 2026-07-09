import Foundation

/// The fixed catalog of "core" exercises offered in `CoreView` during a live
/// workout. There's no server concept of a core group yet, so this list lives
/// on the client: each entry is logged as an *ad-hoc* set (`CompletedSetDTO`
/// with `adhocExerciseName` == the exercise name), and membership in this list
/// is what distinguishes a core set from a regular ad-hoc set in the UI.
///
/// Edit `defaults` to change which exercises appear — no other code depends on
/// the specific contents.
enum CoreExercise {
    static let defaults: [String] = [
        "Plank",
        "Hanging Leg Raise",
        "Cable Crunch",
        "Russian Twist",
        "Ab Wheel Rollout",
        "Dead Bug",
        "Bicycle Crunch",
        "Mountain Climber",
    ]

    /// True when `name` is one of the core exercises — i.e. an ad-hoc set with
    /// this name should render in `CoreView` rather than the "Ad-hoc" section.
    static func isCore(_ name: String?) -> Bool {
        guard let name else { return false }
        return defaults.contains(name)
    }
}
