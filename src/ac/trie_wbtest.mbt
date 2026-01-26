///|
test {
  let trie = Trie::new()
  trie.add(@immut/array.from_array(["a", "b", "c", "d"]))
  trie.add(@immut/array.from_array(["b", "c", "d"]))
  trie.compute()
  json_inspect(trie.root, content={
    "a": { "b": { "c": { "d": ["a", "b", "c", "d"] } } },
    "b": { "c": { "d": ["b", "c", "d"] } },
  })
  json_inspect(trie.root.follow("a"), content={
    "b": { "c": { "d": ["a", "b", "c", "d"] } },
  })
  json_inspect(trie.root.follow("a").follow("b").suffix, content=[
    { "c": { "d": ["b", "c", "d"] } },
  ])
  json_inspect(
    trie.root
    .follow("a")
    .follow("b")
    .follow("c")
    .follow("d")
    .outputs()
    .map(ia => ia.to_array()),
    content=[["a", "b", "c", "d"], ["b", "c", "d"]],
  )
}
