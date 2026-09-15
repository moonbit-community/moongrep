///|
priv enum WalkFrame {
  Enter(CursorId)
  FinishVisit
  Resume(CursorId)
}

///|
/// Follow indexed control edges, including the full visitor's resume behavior.
pub fn SourceIndex::walk(
  self : SourceIndex,
  cursor : CursorId,
  visitor : (RegionId) -> NodeVisitAction,
) -> Unit {
  let pending = [Enter(cursor)]
  let mut pruned = false
  while pending.pop() is Some(frame) {
    match frame {
      FinishVisit => pruned = false
      Resume(next) => if !pruned { pending.push(Enter(next)) }
      Enter(cursor) =>
        match self.step(cursor) {
          End => pruned = false
          Concat(left, right) => {
            pending.push(Enter(right))
            pending.push(Enter(left))
          }
          Finish(inner) => {
            pending.push(FinishVisit)
            pending.push(Enter(inner))
          }
          AfterContinue(first, second) => {
            pending.push(Resume(second))
            pending.push(Enter(first))
          }
          Visit(region, _) | Scan(region) as step => {
            let full = step is Scan(_)
            if step is Visit(_, next) && next != 0 {
              pending.push(Enter(next))
            }
            match visitor(region) {
              NodeVisitReturn => return
              NodeVisitPrune => pruned = true
              NodeVisitContinue =>
                pending.push(Enter(self.children(region, full~)))
            }
          }
        }
    }
  }
}
