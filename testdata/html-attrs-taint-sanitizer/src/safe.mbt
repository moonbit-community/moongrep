fn safe(raw, child) {
  let attrs = sanitize(@html.Attrs::build().inner_html(raw));
  @html.div(class="x", attrs=attrs, child)
}
