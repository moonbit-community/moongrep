///|
// One collector belongs to one parsed source block. Candidate identity remains
// structural; only published diagnostics are keyed by their complete range.
priv struct StructuralFindingCollector {
  seen : Map[(String, String, Int32, Int32), Unit]
  findings : Array[RuleFinding]
}

///|
fn StructuralFindingCollector::new() -> StructuralFindingCollector {
  { seen: Map([]), findings: [], }
}

///|
fn StructuralFindingCollector::add(
  self : StructuralFindingCollector,
  file : String,
  rule : CompiledRule,
  index : Int32,
  loc : @basic.Location,
) -> Unit {
  let key = (file, rule.rule_id, loc.start.cnum, loc.end.cnum)
  if self.seen.contains(key) {
    return
  }
  self.seen[key] = ()
  self.findings.push({
    file,
    rule_id: rule.rule_id,
    description: rule.description,
    pattern_index: index,
    loc,
  })
}
