///|
/// The parser call form that produced a `CallInfo`.
pub(all) enum CallKind {
  Apply
  DotApply
  Pipe
  RevPipe
} derive(Eq, Debug)

///|
/// One evaluated call argument.
///
/// `index` is the semantic argument index after pipe desugaring. Receivers stay
/// separate; the pipe left-hand side and reverse-pipe right-hand side become
/// argument `0`. `path` is present only when the argument expression can be
/// represented as storage.
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
/// Normalized call facts passed to custom and declarative transfer models.
///
/// The taint engine normalizes normal calls, method calls, pipe calls, and
/// reverse-pipe calls into this structure so transfer logic can be shared.
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
