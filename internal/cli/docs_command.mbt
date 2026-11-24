///|
fn render_docs_list() -> String {
  @docs.docs
  .map(doc => {
    let (name, summary, _) = doc
    "\{name}\t\{summary}"
  })
  .join("\n")
}

///|
fn render_doc_body(name : String) -> String raise {
  if @docs.docs.search_by(doc => {
      let (doc_name, _, _) = doc
      doc_name == name
    })
    is Some(index) {
    let (_, _, body) = @docs.docs[index]
    body
  } else {
    raise new_unknown_document_error(name)
  }
}

///|
/// Renders the output for a `docs --list` or `docs <name>` command.
///
/// Raises `CliError::Usage` for unknown document names and `CliError::Internal`
/// if invoked with a non-`docs` command variant.
pub fn render_docs_command(command : CliCommand) -> String raise {
  match command {
    DocsList => render_docs_list()
    DocsShow(name) => render_doc_body(name)
    _ => raise new_internal_error("expected docs command")
  }
}
