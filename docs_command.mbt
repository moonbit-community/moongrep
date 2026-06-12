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
  match
    @docs.docs.search_by(doc => {
      let (doc_name, _, _) = doc
      doc_name == name
    }) {
    Some(index) => {
      let (_, _, body) = @docs.docs[index]
      body
    }
    None =>
      raise CliError::Usage(message="unknown document: \{name}", exit_code=2)
  }
}

///|
fn render_docs_command(
  command : (String, CliOptions?, String?),
) -> String raise {
  match command {
    ("docs-list", None, None) => render_docs_list()
    ("docs-show", None, Some(name)) => render_doc_body(name)
    _ => fail("expected docs command")
  }
}
