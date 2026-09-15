///|
priv enum GroupCandidateResult {
  GroupHit(Int, @basic.Location)
  GroupNegative
  GroupMiss
}

///|
priv struct EvaluationKey {
  group : Int
  source : Int
  env : Int
} derive(Eq, Hash)

///|
priv struct RegionResult {
  hit : Bool
  rejected : Bool
  pruned : Bool
}

///|
// Expansion counters are observed by white-box complexity tests.
#warnings("-unused_field")
priv struct ScanSession {
  plan : ScanPlan
  index : @cst.SourceIndex
  values : @matching.ValueInterner
  environments : Array[CaptureEnvironment]
  environment_ids : Map[EnvironmentKey, Int]
  projections : Map[(Int, Int), Int]
  candidates : Map[EvaluationKey, GroupCandidateResult]
  regions : Map[EvaluationKey, RegionResult]
  mut candidate_expansions : Int
  mut region_expansions : Int
}

///|
fn ScanSession::new(
  plan : ScanPlan,
  node : @untyped_cst.CstNode,
) -> ScanSession {
  let session : ScanSession = {
    plan,
    index: @cst.SourceIndex::new(node),
    values: @matching.ValueInterner::new(),
    environments: [],
    environment_ids: Map([]),
    projections: Map([]),
    candidates: Map([]),
    regions: Map([]),
    candidate_expansions: 0,
    region_expansions: 0,
  }
  ignore(session.intern_environment([]))
  session
}

///|
fn ScanSession::key(
  self : ScanSession,
  group : Int,
  source : Int,
  env : Int,
) -> EvaluationKey {
  { group, source, env: self.project_environment(env, group), }
}

///|
priv enum EvaluationFrame {
  Candidate(EvaluationKey)
  Positive(EvaluationKey, Array[IndexedCompiledRulePattern], Int)
  AfterThen(
    EvaluationKey,
    Array[IndexedCompiledRulePattern],
    Int,
    Int,
    @basic.Location,
    EvaluationKey
  )
  Region(EvaluationKey)
  AfterCandidate(EvaluationKey, EvaluationKey, @cst.CursorId, Bool)
  AfterLeft(EvaluationKey, EvaluationKey, @cst.CursorId)
  AfterRight(EvaluationKey, RegionResult, EvaluationKey)
  AfterReplay(EvaluationKey, EvaluationKey, @cst.CursorId)
  FinishRegion(EvaluationKey, EvaluationKey)
}

///|
fn ScanSession::candidate(
  self : ScanSession,
  group : Int,
  region : @cst.RegionId,
  env : Int,
) -> GroupCandidateResult {
  let key = self.key(group, region, env)
  self.evaluate(Candidate(key))
  self.candidates[key]
}

///|
fn ScanSession::scan(
  self : ScanSession,
  group : Int,
  region : @cst.RegionId,
  env : Int,
) -> Bool {
  let key = self.key(group, self.index.scan(region), env)
  self.evaluate(Region(key))
  self.succeeds(key)
}

///|
fn ScanSession::succeeds(self : ScanSession, key : EvaluationKey) -> Bool {
  let result = self.regions[key]
  !result.rejected && (!self.plan.groups[key.group].has_positive || result.hit)
}

///|
// Dependencies enter a child rule group or a successor in the source DAG.
// A target may equal the candidate: the rule group still advances.
fn ScanSession::evaluate(self : ScanSession, initial : EvaluationFrame) -> Unit {
  let stack = [initial]
  while stack.pop() is Some(frame) {
    match frame {
      Candidate(key) => {
        if self.candidates.contains(key) {
          continue
        }
        self.candidate_expansions += 1
        let patterns = self.plan.groups[key.group].positive.patterns_for_candidate(
          self.index.candidate(key.source),
        )
        stack.push(Positive(key, patterns, 0))
      }
      Positive(key, patterns, start) =>
        self.evaluate_positive(key, patterns, start, stack)
      AfterThen(key, patterns, next, index, loc, child) =>
        if self.succeeds(child) {
          self.candidates[key] = GroupHit(index, loc)
        } else {
          stack.push(Positive(key, patterns, next))
        }
      Region(key) => {
        if self.regions.contains(key) {
          continue
        }
        self.region_expansions += 1
        match self.index.step(key.source) {
          End =>
            self.regions[key] = { hit: false, rejected: false, pruned: false, }
          Concat(left, right) => {
            let left = { ..key, source: left, }
            stack.push(AfterLeft(key, left, right))
            stack.push(Region(left))
          }
          Visit(region, next) => {
            let candidate = { ..key, source: region, }
            stack.push(AfterCandidate(key, candidate, next, false))
            stack.push(Candidate(candidate))
          }
          Scan(region) => {
            let candidate = { ..key, source: region, }
            stack.push(AfterCandidate(key, candidate, 0, true))
            stack.push(Candidate(candidate))
          }
          Finish(inner) => {
            let inner = { ..key, source: inner, }
            stack.push(FinishRegion(key, inner))
            stack.push(Region(inner))
          }
          AfterContinue(first, second) => {
            let first = { ..key, source: first, }
            stack.push(AfterReplay(key, first, second))
            stack.push(Region(first))
          }
        }
      }
      AfterCandidate(key, candidate, next, full) =>
        match self.candidates[candidate] {
          GroupHit(_, _) =>
            self.evaluate_right(
              key,
              { hit: true, rejected: false, pruned: true, },
              next,
              stack,
            )
          GroupNegative => {
            let group = self.plan.groups[key.group]
            self.evaluate_right(
              key,
              {
                hit: false,
                rejected: group.reject_negative || !group.has_positive,
                pruned: true,
              },
              next,
              stack,
            )
          }
          GroupMiss => {
            let left = {
              ..key,
              source: self.index.children(candidate.source, full~),
            }
            stack.push(AfterLeft(key, left, next))
            stack.push(Region(left))
          }
        }
      FinishRegion(key, inner) =>
        self.regions[key] = { ..self.regions[inner], pruned: false, }
      AfterReplay(key, first, second) => {
        let first = self.regions[first]
        if first.pruned || first.rejected {
          self.regions[key] = first
        } else {
          self.evaluate_right(key, first, second, stack)
        }
      }
      AfterLeft(key, left, right) =>
        self.evaluate_right(key, self.regions[left], right, stack)
      AfterRight(key, left, right) => {
        let right = self.regions[right]
        self.regions[key] = {
          hit: left.hit || right.hit,
          rejected: left.rejected || right.rejected,
          pruned: right.pruned,
        }
      }
    }
  }
}

///|
fn ScanSession::evaluate_right(
  self : ScanSession,
  key : EvaluationKey,
  left : RegionResult,
  right : @cst.CursorId,
  stack : Array[EvaluationFrame],
) -> Unit {
  if left.rejected || right == 0 {
    self.regions[key] = left
  } else {
    let right = { ..key, source: right, }
    stack.push(AfterRight(key, left, right))
    stack.push(Region(right))
  }
}

///|
fn ScanSession::evaluate_positive(
  self : ScanSession,
  key : EvaluationKey,
  patterns : Array[IndexedCompiledRulePattern],
  start : Int,
  stack : Array[EvaluationFrame],
) -> Unit {
  let group = self.plan.groups[key.group]
  for position in start..<patterns.length() {
    let indexed = patterns[position]
    guard self.match_pattern(indexed.pattern, key.source, key.env)
      is Some(matched) else {
      continue
    }
    if group.children[indexed.pattern_index] is Some(child) {
      guard matched.target is Some(target) else { continue }
      let env = self.target_environment(
        indexed.pattern,
        matched,
        key.env,
        child,
      )
      let child = self.key(child, self.index.scan(target.region), env)
      stack.push(
        AfterThen(
          key,
          patterns,
          position + 1,
          indexed.pattern_index,
          matched.result.loc,
          child,
        ),
      )
      stack.push(Region(child))
      return
    }
    self.candidates[key] = GroupHit(indexed.pattern_index, matched.result.loc)
    return
  }
  for
    indexed in group.negative.patterns_for_candidate(
      self.index.candidate(key.source),
    ) {
    if self.match_pattern(indexed.pattern, key.source, key.env) is Some(_) {
      self.candidates[key] = GroupNegative
      return
    }
  }
  self.candidates[key] = GroupMiss
}
