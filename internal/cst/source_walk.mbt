///|
/// Walk candidates in order. Pruning skips descendants but retains siblings;
/// returning stops the entire traversal.
pub fn SourceIndex::walk(
  self : SourceIndex,
  cursor : CursorId,
  visitor : (RegionId) -> NodeVisitAction,
) -> Unit {
  let pending = [cursor]
  while pending.pop() is Some(cursor) {
    match self.step(cursor) {
      End => ()
      Concat(left, right) => {
        pending.push(right)
        pending.push(left)
      }
      Visit(region, next) => {
        if next != 0 {
          pending.push(next)
        }
        match visitor(region) {
          NodeVisitReturn => return
          NodeVisitPrune => ()
          NodeVisitContinue => pending.push(self.children(region))
        }
      }
    }
  }
}
