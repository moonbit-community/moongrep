///|
priv struct State {
  storage : Array[TaintValue]
  values : Array[TaintValue]
} derive(Eq)

///|
fn State::empty(graph : @cfg.Graph) -> State {
  {
    storage: Array::make(graph.bindings.length(), TaintValue::clean()),
    values: Array::make(graph.value_count, TaintValue::clean()),
  }
}

///|
fn State::copy(self : State) -> State {
  { storage: self.storage.copy(), values: self.values.copy(), }
}

///|
fn State::join(a : State, b : State) -> State {
  {
    storage: Array::makei(a.storage.length(), i => {
      a.storage[i].join(b.storage[i])
    }),
    values: Array::makei(a.values.length(), i => a.values[i].join(b.values[i])),
  }
}

///|
fn State::write(self : State, path : StoragePath, value : TaintValue) -> Unit {
  self.storage[path.root.0] = self.storage[path.root.0].write(
    path.segments,
    value,
  )
}

///|
fn State::apply(self : State, outcome : CallOutcome) -> Unit {
  for write in outcome.writes {
    match write {
      Set(path, value) => self.write(path, value)
      Sanitize(path) =>
        self.storage[path.root.0] = self.storage[path.root.0].sanitize(
          path.segments,
        )
    }
  }
}

///|
fn State::instructions(self : State, block : @cfg.Block) -> Unit {
  for instruction in block.instructions {
    let value = match instruction.operation {
      Clean => TaintValue::clean()
      Read(path) => self.storage[path.root.0].project(path.segments)
      Project(value, segment) => self.values[value.0].project([segment])
      Update(base, segment, value) =>
        self.values[base.0].write([segment], self.values[value.0])
      Compute(values) => {
        let mut result = TaintValue::clean()
        for value in values {
          result = result.join(self.values[value.0].collapse())
        }
        result
      }
      Write(path, value) => {
        self.write(path, self.values[value.0])
        TaintValue::clean()
      }
    }
    self.values[instruction.result.0] = value
  }
}

///|
fn call_info(call : @cfg.CallSite, state : State) -> CallInfo {
  {
    kind: call.kind,
    cst: call.cst,
    loc: call.loc,
    callee_name: call.callee_name,
    callee_binding: call.callee_binding,
    receiver_path: call.receiver.bind(receiver => receiver.path),
    receiver_site: call.receiver.map(receiver => {
      site(receiver.loc, receiver.path)
    }),
    receiver_taint: call.receiver
    .map(receiver => state.values[receiver.value.0])
    .unwrap_or(TaintValue::clean()),
    arguments: call.arguments.map(arg => {
      index: arg.index,
      label: arg.label,
      expr: arg.expr,
      loc: arg.loc,
      path: arg.path,
      site: site(arg.loc, arg.path),
      taint: state.values[arg.value.0],
    }),
  }
}

///|
fn site(loc : @basic.Location, path : StoragePath?) -> @domain.ValueSite {
  if path is Some(path) {
    Path(path)
  } else {
    Expr(loc, None)
  }
}
