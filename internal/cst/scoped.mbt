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
    Expr_Let
    | Expr_LetMut
    | Expr_LetFn
    | Expr_LetAnd
    | Expr_Guard
    | Expr_Defer
    | Expr_ErrDefer => true
    _ => false
  }
}
