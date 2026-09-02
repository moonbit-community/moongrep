///|
/// Tracks directory identities across one traversal.
pub struct VisitedDirectories {
  identities : Set[String]
}

///|
/// Creates an empty directory identity tracker.
pub fn VisitedDirectories::new() -> VisitedDirectories {
  { identities: Set([]), }
}

///|
/// Resolves `path` and returns whether its directory is being visited for the
/// first time.
pub async fn VisitedDirectories::should_enter(
  self : VisitedDirectories,
  path : String,
) -> Bool {
  self.identities.add_and_check(@fs.realpath(path))
}
