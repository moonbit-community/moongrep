///|
fn ScanSession::apply_toplevel_group(
  self : ScanSession,
  file : String,
  entry : CstStructuralRuleEntry,
  node : @untyped_cst.CstNode,
  collector : StructuralFindingCollector,
) -> Unit {
  let region = self.index.direct(self.index.node_id(node))
  for
    indexed in entry.inside_pattern_buckets.patterns_for_candidate(
      self.index.candidate(region),
    ) {
    if self.match_pattern(indexed.pattern, region, 0) is Some(matched) {
      if matched.target is Some(target) {
        let env = self.target_environment(matched, 0, entry.group)
        if self.scan(entry.group, target.region, env) {
          // Publish only after the entire selected context passes its negatives.
          if self.plan.groups[entry.group].has_positive {
            self.index.walk(self.index.scan(target.region), fn(candidate) {
              self.publication_visits += 1
              match self.candidate(entry.group, candidate, env) {
                GroupHit(index, loc) => {
                  collector.add(file, entry.rule, index, loc)
                  NodeVisitPrune
                }
                GroupNegative => NodeVisitPrune
                GroupMiss => NodeVisitContinue
              }
            })
          } else {
            collector.add(file, entry.rule, 0, matched.result.loc)
          }
        }
      }
      // Only the first matching top-level shape selects a context.
      return
    }
  }
}
