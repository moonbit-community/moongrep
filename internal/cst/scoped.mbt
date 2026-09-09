///|
/// Direct nodes retain their CST. Sequences borrow their statement list.
pub(all) enum ExprMatchCandidate {
  Direct(@untyped_cst.CstNode)
  Sequence(ArrayView[@untyped_cst.CstNode])
}

///|
pub(all) enum NodeVisitAction {
  NodeVisitContinue
  NodeVisitPrune
  NodeVisitReturn
}

///|
fn continuation_owner(kind : @untyped_cst.NodeKind) -> Bool {
  match kind {
    @untyped_cst.Expr_Let
    | @untyped_cst.Expr_LetMut
    | @untyped_cst.Expr_LetFn
    | @untyped_cst.Expr_LetAnd
    | @untyped_cst.Expr_Guard
    | @untyped_cst.Expr_Defer
    | @untyped_cst.Expr_ErrDefer => true
    _ => false
  }
}
