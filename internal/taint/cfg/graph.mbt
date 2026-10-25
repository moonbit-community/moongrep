///|
pub(all) struct ValueId(Int32) derive(Eq, Compare, Hash, Debug)

///|
pub(all) struct BlockId(Int32) derive(Eq, Compare, Hash, Debug)

///|
pub(all) struct ScopeId(Int32) derive(Eq, Compare, Hash, Debug)

///|
pub(all) struct Binding {
  id : @domain.BindingId
  name : String
  scope : ScopeId
  parameter : Bool
}

///|
pub(all) enum Operation {
  Clean
  Read(@domain.StoragePath)
  Project(ValueId, @domain.PathSegment)
  Update(ValueId, @domain.PathSegment, ValueId)
  Compute(Array[ValueId])
  Write(@domain.StoragePath, ValueId)
}

///|
pub(all) struct Instruction {
  result : ValueId
  operation : Operation
}

///|
pub(all) struct Edge {
  target : BlockId
  arguments : Array[ValueId]
}

///|
pub(all) enum Terminator {
  Jump(Edge)
  Branch(ValueId, Edge, Edge)
  Invoke(Int32, Edge, Edge)
  Return(ValueId)
  Raise(ValueId)
  Abort
}

///|
pub(all) struct Block {
  parameters : Array[ValueId]
  instructions : Array[Instruction]
  mut terminator : Terminator
  loc : @basic.Location
}

///|
pub(all) struct Argument {
  index : Int32
  label : String?
  expr : @untyped_cst.CstNode
  loc : @basic.Location
  path : @domain.StoragePath?
  value : ValueId
}

///|
pub(all) struct CallSite {
  kind : @model.CallKind
  cst : @untyped_cst.CstNode
  loc : @basic.Location
  callee_name : String?
  callee_binding : @domain.BindingId?
  receiver : Argument?
  arguments : Array[Argument]
  result : ValueId
  error : ValueId
}

///|
pub(all) struct Graph {
  entry : BlockId
  blocks : Array[Block]
  bindings : Array[Binding]
  calls : Array[CallSite]
  value_count : Int32
  scope_count : Int32
  loc : @basic.Location
}

///|
pub fn Terminator::edges(self : Terminator) -> Array[Edge] {
  match self {
    Jump(edge) => [edge]
    Branch(_, yes, no) | Invoke(_, yes, no) => [yes, no]
    Return(_) | Raise(_) | Abort => []
  }
}

///|
pub fn Operation::inputs(self : Operation) -> Array[ValueId] {
  match self {
    Clean | Read(_) => []
    Project(value, _) | Write(_, value) => [value]
    Update(base, _, value) => [base, value]
    Compute(values) => values
  }
}

///|
pub fn Graph::validate(self : Graph) -> Array[String] {
  let errors : Array[String] = []
  if self.value_count < 0 || self.scope_count < 0 {
    return ["negative graph count"]
  }
  fn value_ok(value : ValueId) {
    value.0 >= 0 && value.0 < self.value_count
  }
  fn path_ok(path : @domain.StoragePath) {
    path.root.0 >= 0 && path.root.0 < self.bindings.length()
  }
  if self.entry.0 < 0 || self.entry.0 >= self.blocks.length() {
    errors.push("invalid entry block")
  }
  let definitions : Array[Bool] = Array::make(self.value_count, false)
  fn record_definition(value : ValueId) {
    if !value_ok(value) {
      errors.push("invalid value")
    } else if definitions[value.0] {
      errors.push("duplicate value definition")
    } else {
      definitions[value.0] = true
    }
  }
  for i in 0..<self.bindings.length() {
    let binding = self.bindings[i]
    if binding.id.0 != i {
      errors.push("binding identity mismatch")
    }
    if binding.scope.0 < 0 || binding.scope.0 >= self.scope_count {
      errors.push("invalid scope")
    }
  }
  for block in self.blocks {
    for value in block.parameters {
      record_definition(value)
    }
    for instruction in block.instructions {
      record_definition(instruction.result)
      if !instruction.operation.inputs().all(value_ok) {
        errors.push("invalid instruction input")
      }
      match instruction.operation {
        Read(path) | Write(path, _) =>
          if !path_ok(path) {
            errors.push("invalid binding")
          }
        _ => ()
      }
    }
    for edge in block.terminator.edges() {
      if edge.target.0 < 0 || edge.target.0 >= self.blocks.length() {
        errors.push("invalid edge target")
      } else if edge.arguments.length() !=
        self.blocks[edge.target.0].parameters.length() {
        errors.push("edge arity mismatch")
      }
      if !edge.arguments.all(value_ok) {
        errors.push("invalid edge argument")
      }
    }
    match block.terminator {
      Branch(value, _, _) | Return(value) | Raise(value) =>
        if !value_ok(value) {
          errors.push("invalid terminator value")
        }
      Invoke(call, _, _) =>
        if call < 0 || call >= self.calls.length() {
          errors.push("invalid call")
        }
      _ => ()
    }
  }
  for call in self.calls {
    if call.callee_binding is Some(binding) &&
      (binding.0 < 0 || binding.0 >= self.bindings.length()) {
      errors.push("invalid callee binding")
    }
    record_definition(call.result)
    record_definition(call.error)
    for argument in call.arguments {
      if !value_ok(argument.value) {
        errors.push("invalid argument value")
      }
      if argument.path is Some(path) && !path_ok(path) {
        errors.push("invalid argument binding")
      }
    }
    if call.receiver is Some(receiver) {
      if !value_ok(receiver.value) {
        errors.push("invalid receiver")
      }
      if receiver.path is Some(path) && !path_ok(path) {
        errors.push("invalid receiver binding")
      }
    }
  }
  if errors.is_empty() {
    self.validate_definitions(errors)
  }
  errors
}

///|
pub extend ValueId with Eq::{equal, not_equal}

///|
pub extend ValueId with Debug::{to_repr}

///|
pub extend ValueId with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend ValueId with Hash::{hash, hash_combine}

///|
pub extend BlockId with Eq::{equal, not_equal}

///|
pub extend BlockId with Debug::{to_repr}

///|
pub extend BlockId with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend BlockId with Hash::{hash, hash_combine}

///|
pub extend ScopeId with Eq::{equal, not_equal}

///|
pub extend ScopeId with Debug::{to_repr}

///|
pub extend ScopeId with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend ScopeId with Hash::{hash, hash_combine}
