///|
pub(all) enum NodeKind {
  Accessor_Index
  Accessor_Label
  Accessor_Newtype
  AliasTarget
  ApplyAttr_NoAttr
  Argument
  ArgumentKind_Labelled
  ArgumentKind_LabelledOption
  ArgumentKind_LabelledOptionPun
  ArgumentKind_LabelledPun
  ArgumentKind_Positional
  ArrayPattern_BytesSpread
  ArrayPattern_ConstSpread
  ArrayPattern_Pattern
  ArrayPattern_StringSpread
  ArrayPatterns_Closed
  ArrayPatterns_Closed_PatternList
  ArrayPatterns_Open
  ArrayPatterns_Open_LPatternList
  ArrayPatterns_Open_RPatternList
  Async
  Attribute
  Binder
  Case
  Constant_BigInt
  Constant_Bool
  Constant_Byte
  Constant_Bytes
  Constant_Char
  Constant_Double
  Constant_Float
  Constant_Int
  Constant_Int64
  Constant_Regex
  Constant_String
  Constant_UInt
  Constant_UInt64
  ConstrDecl
  ConstrDecl_ArgList
  ConstrDecl_AttrList
  ConstrDecl_Tag
  ConstrId
  ConstrName
  ConstrParam
  ConstrPatArg
  Constructor
  ConstructorExtraInfo_NoExtraInfo
  ConstructorExtraInfo_Package
  ConstructorExtraInfo_TypeName
  ConstructorExtraInfo_TypeNameWithConstrPackage
  DeclBody_DeclBody
  DeclBody_DeclBody_LocalTypeList
  DeclBody_DeclNone
  DeclBody_DeclStubs
  DerivingDirective
  DerivingDirective_ArgList
  DotDotBinder_Binder
  DotDotBinder_BinderAs
  DotDotBinder_NoBinder
  DotDotBinder_Underscore
  EmbeddedCode_CodeMultilineString
  EmbeddedCode_CodeMultilineString_LiteralList
  EmbeddedCode_CodeString
  ErrorType_DefaultErrorType
  ErrorType_ErrorType
  ErrorType_MaybeError
  ErrorType_NoErrorType
  ErrorType_Noraise
  ExceptionDecl_EnumPayload
  ExceptionDecl_EnumPayload_ConstrList
  ExceptionDecl_NoPayload
  Expr_Apply
  Expr_Apply_ArgumentList
  Expr_Array
  Expr_Array_ExprList
  Expr_ArrayAugmentedSet
  Expr_ArrayGet
  Expr_ArrayGetSlice
  Expr_ArraySet
  Expr_ArraySpread
  Expr_ArraySpread_ElemList
  Expr_As
  Expr_Assign
  Expr_Break
  Expr_BytesInterp
  Expr_BytesInterp_ElemList
  Expr_Constant
  Expr_Constr
  Expr_Constraint
  Expr_Continue
  Expr_Continue_ExprList
  Expr_Defer
  Expr_DotApply
  Expr_DotApply_ArgList
  Expr_Field
  Expr_For
  Expr_For_BindingList
  Expr_For_ContBindingList
  Expr_ForEach
  Expr_ForEach_BinderList
  Expr_ForEach_ContinueBlock
  Expr_ForEach_Init
  Expr_Function
  Expr_Group
  Expr_Guard
  Expr_Hole
  Expr_Ident
  Expr_If
  Expr_Implies
  Expr_Infix
  Expr_Interp
  Expr_Interp_ElemList
  Expr_Is
  Expr_IsLexmatch
  Expr_IsLexmatch_PatternList
  Expr_Let
  Expr_LetAnd
  Expr_LetAnd_BindingList
  Expr_LetFn
  Expr_LetMut
  Expr_Lexmatch
  Expr_Lexmatch_CaseList
  Expr_Lexscan
  Expr_Lexscan_CaseList
  Expr_ListComprehension
  Expr_ListComprehension_Kind_For
  Expr_ListComprehension_Kind_Foreach
  Expr_Map
  Expr_Map_ElemList
  Expr_Match
  Expr_Match_CaseList
  Expr_Method
  Expr_MultilineString
  Expr_MultilineString_ElemList
  Expr_Mutate
  Expr_Pipe
  Expr_ProofAssert
  Expr_ProofLet
  Expr_Quantifier
  Expr_Raise
  Expr_Record
  Expr_Record_FieldList
  Expr_RecordUpdate
  Expr_RecordUpdate_FieldList
  Expr_RegexMatch
  Expr_RegexMatch_Binding
  Expr_RegexMatch_BindingList
  Expr_Return
  Expr_RevPipe
  Expr_Sequence
  Expr_Sequence_ExprList
  Expr_StaticAssert
  Expr_StaticAssert_StaticAssertionList
  Expr_TemplateWriting
  Expr_Try
  Expr_Try_CaseList
  Expr_TryOperator
  Expr_Tuple
  Expr_Tuple_ExprList
  Expr_Unary
  Expr_Unit
  Expr_While
  FieldDecl
  FieldDecl_AttrList
  FieldDef
  FieldName
  FieldPat
  FnKind_Arrow
  FnKind_Lambda
  For_Binding
  For_ContBinding
  ForEach_ContinueBlock
  ForEach_Init
  FunDecl
  FunDecl_AttrList
  FunDecl_ParameterList
  FunDecl_QuantifierList
  Func_Lambda
  Func_Lambda_ParameterList
  FuncStubs_Embedded
  FuncStubs_Import
  Group_Brace
  Group_Paren
  Hole_Incomplete
  Hole_Synthesized
  Hole_Todo
  Impl_TopExpr
  Impl_TopExpr_LocalTypeList
  Impl_TopFuncDef
  Impl_TopImpl
  Impl_TopImpl_AttrList
  Impl_TopImpl_MethodQuantifierList
  Impl_TopImpl_ParamList
  Impl_TopImpl_QuantifierList
  Impl_TopImplRelation
  Impl_TopImplRelation_AttrList
  Impl_TopImplRelation_QuantifierList
  Impl_TopLetDef
  Impl_TopLetDef_AttrList
  Impl_TopTest
  Impl_TopTest_AttrList
  Impl_TopTest_LocalTypeList
  Impl_TopTest_ParamList
  Impl_TopTrait
  Impl_TopTypeDef
  Impl_TopUsing
  Impl_TopUsing_AttrList
  Impl_TopUsing_NameList
  Impl_TopView
  Impl_TopView_AttrList
  Impl_TopView_ConstrList
  Impl_TopView_ParameterList
  Impl_TopView_QuantifierList
  ImplList
  InterpElem_Expr
  InterpElem_Literal
  InterpElem_Source
  Label
  LetAnd_Binding
  LexCase
  LexCase_PatternList
  LexScanCase
  LexScanCasePattern_Binder
  LexScanCasePattern_Pattern
  LexScanCasePattern_Wildcard
  LexPattern_Alias
  LexPattern_ConstantRef
  LexPattern_Regex
  LexPattern_RegexInterp
  LexPattern_RegexInterp_InterpElemList
  LexPattern_Sequence
  LexPattern_Sequence_PatternList
  LexTopPattern_Binder
  LexTopPattern_Pattern
  LexTopPattern_Wildcard
  LongIdent_Dot
  LongIdent_Ident
  MapExprElem
  MapPatElem
  MultilineString_Interp
  MultilineString_Interp_ElemList
  MultilineString_String
  Parameter_DiscardPositional
  Parameter_Labelled
  Parameter_Optional
  Parameter_Positional
  Parameter_QuestionOptional
  Pattern_Alias
  Pattern_Any
  Pattern_Array
  Pattern_Constant
  Pattern_Constr
  Pattern_Constr_ArgList
  Pattern_Constraint
  Pattern_Map
  Pattern_Map_ElemList
  Pattern_Or
  Pattern_Range
  Pattern_Record
  Pattern_Record_FieldList
  Pattern_SpecialConstr
  Pattern_SpecialConstr_ArgList
  Pattern_Tuple
  Pattern_Tuple_PatternList
  Pattern_Var
  RangeKind_Exclusive
  RangeKind_Inclusive
  RegexPattern_Alias
  RegexPattern_Alternation
  RegexPattern_Literal
  RegexPattern_Reference
  RegexPattern_Sequence
  SpreadableElem_Regular
  SpreadableElem_Spread
  StaticAssertion
  TestName
  Trailing_Comma
  Trailing_None
  Trailing_Semi
  TraitDecl
  TraitDecl_AttrList
  TraitDecl_MethodList
  TraitDecl_SuperList
  TraitMethodDecl
  TraitMethodDecl_AttrList
  TraitMethodDecl_HasDefault
  TraitMethodDecl_ParamList
  TraitMethodDecl_QuantifierList
  TryOperatorKind_Exclamation
  TryOperatorKind_Question
  Type_Any
  Type_Arrow
  Type_Arrow_ArgList
  Type_Name
  Type_Name_TypeList
  Type_Object
  Type_Option
  Type_Tuple
  Type_Tuple_TypeList
  TypeDecl
  TypeDecl_AttrList
  TypeDecl_DerivingList
  TypeDecl_ParamList
  TypeDeclBinder
  TypeDesc_Abstract
  TypeDesc_Alias
  TypeDesc_Error
  TypeDesc_ExtendEnum
  TypeDesc_ExtendEnum_ConstrList
  TypeDesc_ExtensibleEnum
  TypeDesc_ExtensibleEnum_ConstrList
  TypeDesc_Record
  TypeDesc_Record_FieldList
  TypeDesc_TupleStruct
  TypeDesc_TupleStruct_TypeList
  TypeDesc_Variant
  TypeDesc_Variant_ConstrList
  TypeName
  TypeVarBinder
  TypeVarBinder_TypeVarConstraintList
  TypeVarConstraint
  UsingName
  Var
  Visibility_Default
  Visibility_Priv
  Visibility_Pub
  WhereClause
  WhereClause_FieldList
  Leaf(NodePayload)
} derive(Eq, Debug)

///|
pub(all) enum NodePayload {
  PNull
  PNumber(Double, repr~ : String?)
  PString(String)
  PBool(Bool)
} derive(Eq, Debug)

///|
pub fn NodeKind::to_string(self : NodeKind) -> String {
  match self {
    Accessor_Index => "Accessor::Index"
    Accessor_Label => "Accessor::Label"
    Accessor_Newtype => "Accessor::Newtype"
    AliasTarget => "AliasTarget"
    ApplyAttr_NoAttr => "ApplyAttr::NoAttr"
    Argument => "Argument"
    ArgumentKind_Labelled => "ArgumentKind::Labelled"
    ArgumentKind_LabelledOption => "ArgumentKind::LabelledOption"
    ArgumentKind_LabelledOptionPun => "ArgumentKind::LabelledOptionPun"
    ArgumentKind_LabelledPun => "ArgumentKind::LabelledPun"
    ArgumentKind_Positional => "ArgumentKind::Positional"
    ArrayPattern_BytesSpread => "ArrayPattern::BytesSpread"
    ArrayPattern_ConstSpread => "ArrayPattern::ConstSpread"
    ArrayPattern_Pattern => "ArrayPattern::Pattern"
    ArrayPattern_StringSpread => "ArrayPattern::StringSpread"
    ArrayPatterns_Closed => "ArrayPatterns::Closed"
    ArrayPatterns_Closed_PatternList => "ArrayPatterns::Closed::PatternList"
    ArrayPatterns_Open => "ArrayPatterns::Open"
    ArrayPatterns_Open_LPatternList => "ArrayPatterns::Open::LPatternList"
    ArrayPatterns_Open_RPatternList => "ArrayPatterns::Open::RPatternList"
    Async => "Async"
    Attribute => "Attribute"
    Binder => "Binder"
    Case => "Case"
    Constant_BigInt => "Constant::BigInt"
    Constant_Bool => "Constant::Bool"
    Constant_Byte => "Constant::Byte"
    Constant_Bytes => "Constant::Bytes"
    Constant_Char => "Constant::Char"
    Constant_Double => "Constant::Double"
    Constant_Float => "Constant::Float"
    Constant_Int => "Constant::Int"
    Constant_Int64 => "Constant::Int64"
    Constant_Regex => "Constant::Regex"
    Constant_String => "Constant::String"
    Constant_UInt => "Constant::UInt"
    Constant_UInt64 => "Constant::UInt64"
    ConstrDecl => "ConstrDecl"
    ConstrDecl_ArgList => "ConstrDecl::ArgList"
    ConstrDecl_AttrList => "ConstrDecl::AttrList"
    ConstrDecl_Tag => "ConstrDecl::Tag"
    ConstrId => "ConstrId"
    ConstrName => "ConstrName"
    ConstrParam => "ConstrParam"
    ConstrPatArg => "ConstrPatArg"
    Constructor => "Constructor"
    ConstructorExtraInfo_NoExtraInfo => "ConstructorExtraInfo::NoExtraInfo"
    ConstructorExtraInfo_Package => "ConstructorExtraInfo::Package"
    ConstructorExtraInfo_TypeName => "ConstructorExtraInfo::TypeName"
    ConstructorExtraInfo_TypeNameWithConstrPackage =>
      "ConstructorExtraInfo::TypeNameWithConstrPackage"
    DeclBody_DeclBody => "DeclBody::DeclBody"
    DeclBody_DeclBody_LocalTypeList => "DeclBody::DeclBody::LocalTypeList"
    DeclBody_DeclNone => "DeclBody::DeclNone"
    DeclBody_DeclStubs => "DeclBody::DeclStubs"
    DerivingDirective => "DerivingDirective"
    DerivingDirective_ArgList => "DerivingDirective::ArgList"
    DotDotBinder_Binder => "DotDotBinder::Binder"
    DotDotBinder_BinderAs => "DotDotBinder::BinderAs"
    DotDotBinder_NoBinder => "DotDotBinder::NoBinder"
    DotDotBinder_Underscore => "DotDotBinder::Underscore"
    EmbeddedCode_CodeMultilineString => "EmbeddedCode::CodeMultilineString"
    EmbeddedCode_CodeMultilineString_LiteralList =>
      "EmbeddedCode::CodeMultilineString::LiteralList"
    EmbeddedCode_CodeString => "EmbeddedCode::CodeString"
    ErrorType_DefaultErrorType => "ErrorType::DefaultErrorType"
    ErrorType_ErrorType => "ErrorType::ErrorType"
    ErrorType_MaybeError => "ErrorType::MaybeError"
    ErrorType_NoErrorType => "ErrorType::NoErrorType"
    ErrorType_Noraise => "ErrorType::Noraise"
    ExceptionDecl_EnumPayload => "ExceptionDecl::EnumPayload"
    ExceptionDecl_EnumPayload_ConstrList =>
      "ExceptionDecl::EnumPayload::ConstrList"
    ExceptionDecl_NoPayload => "ExceptionDecl::NoPayload"
    Expr_Apply => "Expr::Apply"
    Expr_Apply_ArgumentList => "Expr::Apply::ArgumentList"
    Expr_Array => "Expr::Array"
    Expr_Array_ExprList => "Expr::Array::ExprList"
    Expr_ArrayAugmentedSet => "Expr::ArrayAugmentedSet"
    Expr_ArrayGet => "Expr::ArrayGet"
    Expr_ArrayGetSlice => "Expr::ArrayGetSlice"
    Expr_ArraySet => "Expr::ArraySet"
    Expr_ArraySpread => "Expr::ArraySpread"
    Expr_ArraySpread_ElemList => "Expr::ArraySpread::ElemList"
    Expr_As => "Expr::As"
    Expr_Assign => "Expr::Assign"
    Expr_Break => "Expr::Break"
    Expr_BytesInterp => "Expr::BytesInterp"
    Expr_BytesInterp_ElemList => "Expr::BytesInterp::ElemList"
    Expr_Constant => "Expr::Constant"
    Expr_Constr => "Expr::Constr"
    Expr_Constraint => "Expr::Constraint"
    Expr_Continue => "Expr::Continue"
    Expr_Continue_ExprList => "Expr::Continue::ExprList"
    Expr_Defer => "Expr::Defer"
    Expr_DotApply => "Expr::DotApply"
    Expr_DotApply_ArgList => "Expr::DotApply::ArgList"
    Expr_Field => "Expr::Field"
    Expr_For => "Expr::For"
    Expr_For_BindingList => "Expr::For::BindingList"
    Expr_For_ContBindingList => "Expr::For::ContBindingList"
    Expr_ForEach => "Expr::ForEach"
    Expr_ForEach_BinderList => "Expr::ForEach::BinderList"
    Expr_ForEach_ContinueBlock => "Expr::ForEach::ContinueBlock"
    Expr_ForEach_Init => "Expr::ForEach::Init"
    Expr_Function => "Expr::Function"
    Expr_Group => "Expr::Group"
    Expr_Guard => "Expr::Guard"
    Expr_Hole => "Expr::Hole"
    Expr_Ident => "Expr::Ident"
    Expr_If => "Expr::If"
    Expr_Implies => "Expr::Implies"
    Expr_Infix => "Expr::Infix"
    Expr_Interp => "Expr::Interp"
    Expr_Interp_ElemList => "Expr::Interp::ElemList"
    Expr_Is => "Expr::Is"
    Expr_IsLexmatch => "Expr::IsLexmatch"
    Expr_IsLexmatch_PatternList => "Expr::IsLexmatch::PatternList"
    Expr_Let => "Expr::Let"
    Expr_LetAnd => "Expr::LetAnd"
    Expr_LetAnd_BindingList => "Expr::LetAnd::BindingList"
    Expr_LetFn => "Expr::LetFn"
    Expr_LetMut => "Expr::LetMut"
    Expr_Lexmatch => "Expr::Lexmatch"
    Expr_Lexmatch_CaseList => "Expr::Lexmatch::CaseList"
    Expr_Lexscan => "Expr::Lexscan"
    Expr_Lexscan_CaseList => "Expr::Lexscan::CaseList"
    Expr_ListComprehension => "Expr::ListComprehension"
    Expr_ListComprehension_Kind_For => "Expr::ListComprehension::Kind::For"
    Expr_ListComprehension_Kind_Foreach =>
      "Expr::ListComprehension::Kind::Foreach"
    Expr_Map => "Expr::Map"
    Expr_Map_ElemList => "Expr::Map::ElemList"
    Expr_Match => "Expr::Match"
    Expr_Match_CaseList => "Expr::Match::CaseList"
    Expr_Method => "Expr::Method"
    Expr_MultilineString => "Expr::MultilineString"
    Expr_MultilineString_ElemList => "Expr::MultilineString::ElemList"
    Expr_Mutate => "Expr::Mutate"
    Expr_Pipe => "Expr::Pipe"
    Expr_ProofAssert => "Expr::ProofAssert"
    Expr_ProofLet => "Expr::ProofLet"
    Expr_Quantifier => "Expr::Quantifier"
    Expr_Raise => "Expr::Raise"
    Expr_Record => "Expr::Record"
    Expr_Record_FieldList => "Expr::Record::FieldList"
    Expr_RecordUpdate => "Expr::RecordUpdate"
    Expr_RecordUpdate_FieldList => "Expr::RecordUpdate::FieldList"
    Expr_RegexMatch => "Expr::RegexMatch"
    Expr_RegexMatch_Binding => "Expr::RegexMatch::Binding"
    Expr_RegexMatch_BindingList => "Expr::RegexMatch::BindingList"
    Expr_Return => "Expr::Return"
    Expr_RevPipe => "Expr::RevPipe"
    Expr_Sequence => "Expr::Sequence"
    Expr_Sequence_ExprList => "Expr::Sequence::ExprList"
    Expr_StaticAssert => "Expr::StaticAssert"
    Expr_StaticAssert_StaticAssertionList =>
      "Expr::StaticAssert::StaticAssertionList"
    Expr_TemplateWriting => "Expr::TemplateWriting"
    Expr_Try => "Expr::Try"
    Expr_Try_CaseList => "Expr::Try::CaseList"
    Expr_TryOperator => "Expr::TryOperator"
    Expr_Tuple => "Expr::Tuple"
    Expr_Tuple_ExprList => "Expr::Tuple::ExprList"
    Expr_Unary => "Expr::Unary"
    Expr_Unit => "Expr::Unit"
    Expr_While => "Expr::While"
    FieldDecl => "FieldDecl"
    FieldDecl_AttrList => "FieldDecl::AttrList"
    FieldDef => "FieldDef"
    FieldName => "FieldName"
    FieldPat => "FieldPat"
    FnKind_Arrow => "FnKind::Arrow"
    FnKind_Lambda => "FnKind::Lambda"
    For_Binding => "For::Binding"
    For_ContBinding => "For::ContBinding"
    ForEach_ContinueBlock => "ForEach::ContinueBlock"
    ForEach_Init => "ForEach::Init"
    FunDecl => "FunDecl"
    FunDecl_AttrList => "FunDecl::AttrList"
    FunDecl_ParameterList => "FunDecl::ParameterList"
    FunDecl_QuantifierList => "FunDecl::QuantifierList"
    Func_Lambda => "Func::Lambda"
    Func_Lambda_ParameterList => "Func::Lambda::ParameterList"
    FuncStubs_Embedded => "FuncStubs::Embedded"
    FuncStubs_Import => "FuncStubs::Import"
    Group_Brace => "Group::Brace"
    Group_Paren => "Group::Paren"
    Hole_Incomplete => "Hole::Incomplete"
    Hole_Synthesized => "Hole::Synthesized"
    Hole_Todo => "Hole::Todo"
    Impl_TopExpr => "Impl::TopExpr"
    Impl_TopExpr_LocalTypeList => "Impl::TopExpr::LocalTypeList"
    Impl_TopFuncDef => "Impl::TopFuncDef"
    Impl_TopImpl => "Impl::TopImpl"
    Impl_TopImpl_AttrList => "Impl::TopImpl::AttrList"
    Impl_TopImpl_MethodQuantifierList => "Impl::TopImpl::MethodQuantifierList"
    Impl_TopImpl_ParamList => "Impl::TopImpl::ParamList"
    Impl_TopImpl_QuantifierList => "Impl::TopImpl::QuantifierList"
    Impl_TopImplRelation => "Impl::TopImplRelation"
    Impl_TopImplRelation_AttrList => "Impl::TopImplRelation::AttrList"
    Impl_TopImplRelation_QuantifierList =>
      "Impl::TopImplRelation::QuantifierList"
    Impl_TopLetDef => "Impl::TopLetDef"
    Impl_TopLetDef_AttrList => "Impl::TopLetDef::AttrList"
    Impl_TopTest => "Impl::TopTest"
    Impl_TopTest_AttrList => "Impl::TopTest::AttrList"
    Impl_TopTest_LocalTypeList => "Impl::TopTest::LocalTypeList"
    Impl_TopTest_ParamList => "Impl::TopTest::ParamList"
    Impl_TopTrait => "Impl::TopTrait"
    Impl_TopTypeDef => "Impl::TopTypeDef"
    Impl_TopUsing => "Impl::TopUsing"
    Impl_TopUsing_AttrList => "Impl::TopUsing::AttrList"
    Impl_TopUsing_NameList => "Impl::TopUsing::NameList"
    Impl_TopView => "Impl::TopView"
    Impl_TopView_AttrList => "Impl::TopView::AttrList"
    Impl_TopView_ConstrList => "Impl::TopView::ConstrList"
    Impl_TopView_ParameterList => "Impl::TopView::ParameterList"
    Impl_TopView_QuantifierList => "Impl::TopView::QuantifierList"
    ImplList => "ImplList"
    InterpElem_Expr => "InterpElem::Expr"
    InterpElem_Literal => "InterpElem::Literal"
    InterpElem_Source => "InterpElem::Source"
    Label => "Label"
    LetAnd_Binding => "LetAnd::Binding"
    LexCase => "LexCase"
    LexCase_PatternList => "LexCase::PatternList"
    LexScanCase => "LexscanCase"
    LexScanCasePattern_Binder => "LexscanCasePattern::Binder"
    LexScanCasePattern_Pattern => "LexscanCasePattern::Pattern"
    LexScanCasePattern_Wildcard => "LexscanCasePattern::Wildcard"
    LexPattern_Alias => "LexPattern::Alias"
    LexPattern_ConstantRef => "LexPattern::ConstantRef"
    LexPattern_Regex => "LexPattern::Regex"
    LexPattern_RegexInterp => "LexPattern::RegexInterp"
    LexPattern_RegexInterp_InterpElemList =>
      "LexPattern::RegexInterp::InterpElemList"
    LexPattern_Sequence => "LexPattern::Sequence"
    LexPattern_Sequence_PatternList => "LexPattern::Sequence::PatternList"
    LexTopPattern_Binder => "LexTopPattern::Binder"
    LexTopPattern_Pattern => "LexTopPattern::Pattern"
    LexTopPattern_Wildcard => "LexTopPattern::Wildcard"
    LongIdent_Dot => "LongIdent::Dot"
    LongIdent_Ident => "LongIdent::Ident"
    MapExprElem => "MapExprElem"
    MapPatElem => "MapPatElem"
    MultilineString_Interp => "MultilineString::Interp"
    MultilineString_Interp_ElemList => "MultilineString::Interp::ElemList"
    MultilineString_String => "MultilineString::String"
    Parameter_DiscardPositional => "Parameter::DiscardPositional"
    Parameter_Labelled => "Parameter::Labelled"
    Parameter_Optional => "Parameter::Optional"
    Parameter_Positional => "Parameter::Positional"
    Parameter_QuestionOptional => "Parameter::QuestionOptional"
    Pattern_Alias => "Pattern::Alias"
    Pattern_Any => "Pattern::Any"
    Pattern_Array => "Pattern::Array"
    Pattern_Constant => "Pattern::Constant"
    Pattern_Constr => "Pattern::Constr"
    Pattern_Constr_ArgList => "Pattern::Constr::ArgList"
    Pattern_Constraint => "Pattern::Constraint"
    Pattern_Map => "Pattern::Map"
    Pattern_Map_ElemList => "Pattern::Map::ElemList"
    Pattern_Or => "Pattern::Or"
    Pattern_Range => "Pattern::Range"
    Pattern_Record => "Pattern::Record"
    Pattern_Record_FieldList => "Pattern::Record::FieldList"
    Pattern_SpecialConstr => "Pattern::SpecialConstr"
    Pattern_SpecialConstr_ArgList => "Pattern::SpecialConstr::ArgList"
    Pattern_Tuple => "Pattern::Tuple"
    Pattern_Tuple_PatternList => "Pattern::Tuple::PatternList"
    Pattern_Var => "Pattern::Var"
    RangeKind_Exclusive => "RangeKind::Exclusive"
    RangeKind_Inclusive => "RangeKind::Inclusive"
    RegexPattern_Alias => "RegexPattern::Alias"
    RegexPattern_Alternation => "RegexPattern::Alternation"
    RegexPattern_Literal => "RegexPattern::Literal"
    RegexPattern_Reference => "RegexPattern::Reference"
    RegexPattern_Sequence => "RegexPattern::Sequence"
    SpreadableElem_Regular => "SpreadableElem::Regular"
    SpreadableElem_Spread => "SpreadableElem::Spread"
    StaticAssertion => "StaticAssertion"
    TestName => "TestName"
    Trailing_Comma => "Trailing::Comma"
    Trailing_None => "Trailing::None"
    Trailing_Semi => "Trailing::Semi"
    TraitDecl => "TraitDecl"
    TraitDecl_AttrList => "TraitDecl::AttrList"
    TraitDecl_MethodList => "TraitDecl::MethodList"
    TraitDecl_SuperList => "TraitDecl::SuperList"
    TraitMethodDecl => "TraitMethodDecl"
    TraitMethodDecl_AttrList => "TraitMethodDecl::AttrList"
    TraitMethodDecl_HasDefault => "TraitMethodDecl::HasDefault"
    TraitMethodDecl_ParamList => "TraitMethodDecl::ParamList"
    TraitMethodDecl_QuantifierList => "TraitMethodDecl::QuantifierList"
    TryOperatorKind_Exclamation => "TryOperatorKind::Exclamation"
    TryOperatorKind_Question => "TryOperatorKind::Question"
    Type_Any => "Type::Any"
    Type_Arrow => "Type::Arrow"
    Type_Arrow_ArgList => "Type::Arrow::ArgList"
    Type_Name => "Type::Name"
    Type_Name_TypeList => "Type::Name::TypeList"
    Type_Object => "Type::Object"
    Type_Option => "Type::Option"
    Type_Tuple => "Type::Tuple"
    Type_Tuple_TypeList => "Type::Tuple::TypeList"
    TypeDecl => "TypeDecl"
    TypeDecl_AttrList => "TypeDecl::AttrList"
    TypeDecl_DerivingList => "TypeDecl::DerivingList"
    TypeDecl_ParamList => "TypeDecl::ParamList"
    TypeDeclBinder => "TypeDeclBinder"
    TypeDesc_Abstract => "TypeDesc::Abstract"
    TypeDesc_Alias => "TypeDesc::Alias"
    TypeDesc_Error => "TypeDesc::Error"
    TypeDesc_ExtendEnum => "TypeDesc::ExtendEnum"
    TypeDesc_ExtendEnum_ConstrList => "TypeDesc::ExtendEnum::ConstrList"
    TypeDesc_ExtensibleEnum => "TypeDesc::ExtensibleEnum"
    TypeDesc_ExtensibleEnum_ConstrList => "TypeDesc::ExtensibleEnum::ConstrList"
    TypeDesc_Record => "TypeDesc::Record"
    TypeDesc_Record_FieldList => "TypeDesc::Record::FieldList"
    TypeDesc_TupleStruct => "TypeDesc::TupleStruct"
    TypeDesc_TupleStruct_TypeList => "TypeDesc::TupleStruct::TypeList"
    TypeDesc_Variant => "TypeDesc::Variant"
    TypeDesc_Variant_ConstrList => "TypeDesc::Variant::ConstrList"
    TypeName => "TypeName"
    TypeVarBinder => "TypeVarBinder"
    TypeVarBinder_TypeVarConstraintList =>
      "TypeVarBinder::TypeVarConstraintList"
    TypeVarConstraint => "TypeVarConstraint"
    UsingName => "UsingName"
    Var => "Var"
    Visibility_Default => "Visibility::Default"
    Visibility_Priv => "Visibility::Priv"
    Visibility_Pub => "Visibility::Pub"
    WhereClause => "WhereClause"
    WhereClause_FieldList => "WhereClause::FieldList"
    Leaf(_) => ""
  }
}

///|
pub(all) struct Node {
  kind : NodeKind
  loc : @basic.Location
  children : Array[(String?, Node)]
} derive(Debug)

///|
pub fn Node::to_json(self : Node) -> Json {
  match self.kind {
    Leaf(payload) => payload.to_json()
    _ =>
      if self.kind.has_item_children() {
        items_node_to_json(self.kind, self.loc, self.children)
      } else {
        fields_node_to_json(self.kind, self.loc, self.children)
      }
  }
}

///|
fn fields_node_to_json(
  kind : NodeKind,
  loc : @basic.Location,
  fields : Array[(String?, Node)],
) -> Json {
  let children : Map[String, Json] = {}
  fields.each(fn(field) {
    let (name, node) = field
    if name is Some(name) {
      children[name] = node.to_json()
    }
  })
  { "kind": kind.to_string(), "loc": loc, "children": children }
}

///|
fn items_node_to_json(
  kind : NodeKind,
  loc : @basic.Location,
  items : Array[(String?, Node)],
) -> Json {
  let children : Array[Json] = []
  items.each(fn(item) {
    let (_, node) = item
    children.push(node.to_json())
  })
  { "kind": kind.to_string(), "loc": loc, "children": children }
}

///|
fn NodeKind::has_item_children(self : NodeKind) -> Bool {
  match self {
    ArrayPatterns_Closed_PatternList
    | ArrayPatterns_Open_LPatternList
    | ArrayPatterns_Open_RPatternList
    | ConstrDecl_ArgList
    | ConstrDecl_AttrList
    | DeclBody_DeclBody_LocalTypeList
    | DerivingDirective_ArgList
    | EmbeddedCode_CodeMultilineString_LiteralList
    | ExceptionDecl_EnumPayload_ConstrList
    | Expr_Apply_ArgumentList
    | Expr_ArraySpread_ElemList
    | Expr_Array_ExprList
    | Expr_BytesInterp_ElemList
    | Expr_Continue_ExprList
    | Expr_DotApply_ArgList
    | Expr_ForEach_BinderList
    | Expr_ForEach_ContinueBlock
    | Expr_ForEach_Init
    | Expr_For_BindingList
    | Expr_For_ContBindingList
    | Expr_Interp_ElemList
    | Expr_IsLexmatch_PatternList
    | Expr_LetAnd_BindingList
    | Expr_Lexmatch_CaseList
    | Expr_Lexscan_CaseList
    | Expr_Map_ElemList
    | Expr_Match_CaseList
    | Expr_MultilineString_ElemList
    | Expr_RecordUpdate_FieldList
    | Expr_Record_FieldList
    | Expr_RegexMatch_BindingList
    | Expr_Sequence_ExprList
    | Expr_StaticAssert_StaticAssertionList
    | Expr_Try_CaseList
    | Expr_Tuple_ExprList
    | FieldDecl_AttrList
    | FunDecl_AttrList
    | FunDecl_ParameterList
    | FunDecl_QuantifierList
    | Func_Lambda_ParameterList
    | ImplList
    | Impl_TopExpr_LocalTypeList
    | Impl_TopImplRelation_AttrList
    | Impl_TopImplRelation_QuantifierList
    | Impl_TopImpl_AttrList
    | Impl_TopImpl_MethodQuantifierList
    | Impl_TopImpl_ParamList
    | Impl_TopImpl_QuantifierList
    | Impl_TopLetDef_AttrList
    | Impl_TopTest_AttrList
    | Impl_TopTest_LocalTypeList
    | Impl_TopTest_ParamList
    | Impl_TopUsing_AttrList
    | Impl_TopUsing_NameList
    | Impl_TopView_AttrList
    | Impl_TopView_ConstrList
    | Impl_TopView_ParameterList
    | Impl_TopView_QuantifierList
    | LexCase_PatternList
    | LexPattern_RegexInterp_InterpElemList
    | LexPattern_Sequence_PatternList
    | MultilineString_Interp_ElemList
    | Pattern_Constr_ArgList
    | Pattern_Map_ElemList
    | Pattern_Record_FieldList
    | Pattern_SpecialConstr_ArgList
    | Pattern_Tuple_PatternList
    | TraitDecl_AttrList
    | TraitDecl_MethodList
    | TraitDecl_SuperList
    | TraitMethodDecl_AttrList
    | TraitMethodDecl_ParamList
    | TraitMethodDecl_QuantifierList
    | TypeDecl_AttrList
    | TypeDecl_DerivingList
    | TypeDecl_ParamList
    | TypeDesc_ExtendEnum_ConstrList
    | TypeDesc_ExtensibleEnum_ConstrList
    | TypeDesc_Record_FieldList
    | TypeDesc_TupleStruct_TypeList
    | TypeDesc_Variant_ConstrList
    | TypeVarBinder_TypeVarConstraintList
    | Type_Arrow_ArgList
    | Type_Name_TypeList
    | Type_Tuple_TypeList
    | WhereClause_FieldList => true
    _ => false
  }
}

///|
fn NodePayload::to_json(self : NodePayload) -> Json {
  match self {
    PNull => Json::null()
    PBool(value) => Json::boolean(value)
    PString(value) => Json::string(value)
    PNumber(value, repr~) => Json::number(value, repr?)
  }
}

///|
pub impl ToJson for Node with fn to_json(self) {
  Node::to_json(self)
}
