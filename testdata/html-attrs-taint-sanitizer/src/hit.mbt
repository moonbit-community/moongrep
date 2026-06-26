fn hit(raw, child) {
  let attrs = @html.Attrs::build().inner_html(raw);
  @html.div(class="x", attrs=attrs, child)
}
