///|
pub(all) enum CallKind {
  Apply
  DotApply
  Pipe
  RevPipe
} derive(Eq, Debug)

///|
pub(all) struct CallArgument {
  index : Int
  label : String?
  expr : @syntax.Expr
  loc : @basic.Location
  path : StoragePath?
  site : ValueSite
  taint : TaintTree
}

///|
pub(all) struct CallInfo {
  kind : CallKind
  ast : @syntax.Expr
  loc : @basic.Location
  callee_name : String?
  receiver_path : StoragePath?
  receiver_site : ValueSite?
  receiver_taint : TaintTree
  arguments : Array[CallArgument]
}
