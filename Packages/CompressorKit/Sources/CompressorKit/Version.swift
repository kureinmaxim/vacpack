/// Vacpack's release version for the app and the CLI.
///
/// Synced from `project.yml` by `scripts/update_version.py`; do not edit by hand
/// (see VERSION_MANAGEMENT.md).
public enum VacpackVersion {
    /// Semantic version, MAJOR.MINOR.PATCH.
    public static let number = "0.2.1"
    /// Release date, DD.MM.YYYY.
    public static let releaseDate = "18.10.2026"

    /// "0.1.0 (released 18.10.2026)".
    public static var description: String { "\(number) (released \(releaseDate))" }
}
