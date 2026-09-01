///|
/// The constraint applied to each item captured by an ellipsis metavar.
pub(all) enum EllipsisMetavarKind {
  AnyItem
  ExpItem
  IdItem
  ConstItem
  ArgItem
  PatItem
  TypeItem
} derive(Eq)

///|
/// The semantic kind of one compiled metavar.
pub(all) enum MetavarKind {
  Expr
  Identifier
  Constant
  Argument
  Type
  Pattern
  Ellipsis(EllipsisMetavarKind)
} derive(Eq)

///|
/// One named metavar in source order.
pub(all) struct MetavarEntry {
  name : String
  kind : MetavarKind
}

///|
/// The result of registering one named metavar.
pub(all) enum MetavarRegistration {
  Registered
  AlreadyRegistered
  RegistrationConflict(MetavarKind)
} derive(Eq)

///|
/// Parsed syntax shared by pattern compilation and runtime lookup.
pub(all) enum MetavarSyntax {
  NotMetavar
  InvalidMetavar
  InvalidEllipsisMetavar
  UnsupportedMetavarKind(String)
  UnsupportedEllipsisMetavarKind(String)
  Bare(String)
  Typed(String, MetavarKind)
  EllipsisSyntax(String, EllipsisMetavarKind?)
  Wildcard
} derive(Eq)

///|
/// A placeholder resolved against a compiled registry.
pub(all) enum ResolvedMetavar {
  ResolvedWildcard(MetavarKind?)
  ResolvedNamed(MetavarEntry)
  ResolvedSpecialExpr(String)
}

///|
/// Ordered named metavars plus expression placeholders reserved by a compiler
/// context, such as `__TARGET__` and `__SOURCE__`.
pub(all) struct MetavarRegistry {
  entries : Array[MetavarEntry]
  special_expr_placeholders : Array[String]
}

///|
/// Creates an empty registry.
pub fn MetavarRegistry::new() -> MetavarRegistry {
  { entries: [], special_expr_placeholders: [], }
}

///|
/// Returns an independent copy that can receive context-specific placeholders.
pub fn MetavarRegistry::copy(self : MetavarRegistry) -> MetavarRegistry {
  {
    entries: self.entries.copy(),
    special_expr_placeholders: self.special_expr_placeholders.copy(),
  }
}

///|
/// Registers a named metavar without changing the first declaration's order or
/// kind. Conflicts are reported to the caller so it can retain its diagnostic
/// context.
pub fn MetavarRegistry::register(
  self : MetavarRegistry,
  name : String,
  kind : MetavarKind,
) -> MetavarRegistration {
  for entry in self.entries {
    if entry.name == name {
      if entry.kind == kind {
        return AlreadyRegistered
      }
      return RegistrationConflict(entry.kind)
    }
  }
  self.entries.push({ name, kind, })
  Registered
}

///|
/// Adds a whole-expression placeholder reserved by the surrounding compiler
/// context.
pub fn MetavarRegistry::register_special_expr_placeholder(
  self : MetavarRegistry,
  name : String,
) -> Unit {
  for existing in self.special_expr_placeholders {
    if existing == name {
      return
    }
  }
  self.special_expr_placeholders.push(name)
}

///|
/// Looks up the semantic kind of a named metavar.
pub fn MetavarRegistry::kind_of(
  self : MetavarRegistry,
  name : String,
) -> MetavarKind? {
  for entry in self.entries {
    if entry.name == name {
      return Some(entry.kind)
    }
  }
  None
}

///|
/// Returns named metavars of exactly `kind`, preserving registry order.
pub fn MetavarRegistry::names(
  self : MetavarRegistry,
  kind : MetavarKind,
) -> Array[String] {
  let result : Array[String] = []
  for entry in self.entries {
    if entry.kind == kind {
      result.push(entry.name)
    }
  }
  result
}

///|
/// Resolves source spelling through this registry. The registry's compiled kind
/// is authoritative; an unregistered spelling is not a placeholder.
pub fn MetavarRegistry::resolve(
  self : MetavarRegistry,
  raw : String,
) -> ResolvedMetavar? {
  match parse_metavar_syntax(raw) {
    Wildcard => Some(ResolvedWildcard(None))
    Bare(name) | Typed(name, _) =>
      self.entry_of(name).map(entry => ResolvedNamed(entry))
    EllipsisSyntax(name, explicit_kind) =>
      if name == "_" {
        Some(ResolvedWildcard(Some(Ellipsis(explicit_kind.unwrap_or(AnyItem)))))
      } else {
        match self.entry_of(name) {
          Some(entry) if entry.kind is Ellipsis(_) => Some(ResolvedNamed(entry))
          _ => None
        }
      }
    NotMetavar =>
      if self.is_special_expr_placeholder(raw) {
        Some(ResolvedSpecialExpr(raw))
      } else {
        None
      }
    _ => None
  }
}

///|
/// Returns whether `raw` is the built-in single-node or ellipsis wildcard.
pub fn MetavarRegistry::is_wildcard(
  self : MetavarRegistry,
  raw : String,
) -> Bool {
  self.resolve(raw) is Some(ResolvedWildcard(_))
}

///|
/// Returns whether `raw` denotes a compiled placeholder. Logical names are
/// accepted for CST adapters that already removed the source sigil.
pub fn MetavarRegistry::is_placeholder(
  self : MetavarRegistry,
  raw : String,
) -> Bool {
  if self.kind_of(raw) is Some(_) || self.is_special_expr_placeholder(raw) {
    return true
  }
  match metavar_component(raw) {
    Some(component) if component == raw => self.resolve(raw) is Some(_)
    _ => false
  }
}

///|
fn MetavarRegistry::entry_of(
  self : MetavarRegistry,
  name : String,
) -> MetavarEntry? {
  for entry in self.entries {
    if entry.name == name {
      return Some(entry)
    }
  }
  None
}

///|
fn MetavarRegistry::is_special_expr_placeholder(
  self : MetavarRegistry,
  name : String,
) -> Bool {
  for placeholder in self.special_expr_placeholders {
    if placeholder == name {
      return true
    }
  }
  false
}

///|
/// Parses a bare, typed, ellipsis, qualified, or wildcard metavar spelling.
pub fn parse_metavar_syntax(raw : String) -> MetavarSyntax {
  guard metavar_component(raw) is Some(component) else { return NotMetavar }
  if component == "$_" {
    return if component == raw { Wildcard } else { InvalidMetavar }
  }
  if component.has_prefix("$$$") {
    let syntax = parse_ellipsis_metavar_component(component)
    return match syntax {
      EllipsisSyntax("_", _) if component != raw => InvalidEllipsisMetavar
      _ => syntax
    }
  }
  if component.has_prefix("$(") {
    return parse_typed_metavar_component(component)
  }
  if component.has_prefix("$") && component.length() > 1 {
    return Bare(component[1:].to_owned())
  }
  InvalidMetavar
}

///|
fn parse_typed_metavar_component(component : String) -> MetavarSyntax {
  if !component.has_suffix(")") {
    return InvalidMetavar
  }
  let end = component.length() - 1
  for index in 2..<end {
    if component[index] == ':' {
      let name = component[2:index].trim()
      let kind_text = component[index + 1:end].trim()
      if name.is_empty() || kind_text.is_empty() {
        return InvalidMetavar
      }
      return if parse_single_metavar_kind(kind_text) is Some(kind) {
        Typed(name.to_owned(), kind)
      } else {
        UnsupportedMetavarKind(kind_text.to_owned())
      }
    }
  }
  InvalidMetavar
}

///|
fn parse_ellipsis_metavar_component(component : String) -> MetavarSyntax {
  if component.has_prefix("$$$(") {
    if !component.has_suffix(")") {
      return InvalidEllipsisMetavar
    }
    let end = component.length() - 1
    for index in 4..<end {
      if component[index] == ':' {
        let name = component[4:index].trim()
        let kind_text = component[index + 1:end].trim()
        if name.is_empty() || kind_text.is_empty() {
          return InvalidEllipsisMetavar
        }
        return if parse_ellipsis_metavar_kind(kind_text) is Some(kind) {
          EllipsisSyntax(name.to_owned(), Some(kind))
        } else {
          UnsupportedEllipsisMetavarKind(kind_text.to_owned())
        }
      }
    }
    InvalidEllipsisMetavar
  } else if component.length() > 3 {
    EllipsisSyntax(component[3:].to_owned(), None)
  } else {
    InvalidEllipsisMetavar
  }
}

///|
fn parse_single_metavar_kind(raw : StringView) -> MetavarKind? {
  match raw {
    "exp" => Some(Expr)
    "id" => Some(Identifier)
    "const" => Some(Constant)
    "arg" => Some(Argument)
    "type" => Some(Type)
    "pat" => Some(Pattern)
    _ => None
  }
}

///|
fn parse_ellipsis_metavar_kind(raw : StringView) -> EllipsisMetavarKind? {
  match raw {
    "exp" => Some(ExpItem)
    "id" => Some(IdItem)
    "const" => Some(ConstItem)
    "arg" => Some(ArgItem)
    "pat" => Some(PatItem)
    "type" => Some(TypeItem)
    _ => None
  }
}

///|
fn metavar_component(raw : String) -> String? {
  let mut start = -1
  for index in 0..<raw.length() {
    if raw[index] == '$' && (index == 0 || raw[index - 1] != '$') {
      start = index
    }
  }
  if start < 0 {
    None
  } else {
    Some(raw[start:].to_owned())
  }
}

///|
/// Returns the rule-syntax name used in diagnostics for a single-node kind.
pub fn MetavarKind::syntax_name(self : MetavarKind) -> String {
  match self {
    Expr => "exp"
    Identifier => "id"
    Constant => "const"
    Argument => "arg"
    Type => "type"
    Pattern => "pat"
    Ellipsis(_) => "ellipsis"
  }
}

///|
/// Returns the rule-syntax name used for an ellipsis item constraint.
pub fn EllipsisMetavarKind::syntax_name(self : EllipsisMetavarKind) -> String {
  match self {
    AnyItem => "any"
    ExpItem => "exp"
    IdItem => "id"
    ConstItem => "const"
    ArgItem => "arg"
    PatItem => "pat"
    TypeItem => "type"
  }
}
