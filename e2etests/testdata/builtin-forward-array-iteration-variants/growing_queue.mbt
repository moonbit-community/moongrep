///|
struct Node {
  edges : Map[Char, Int]
  mut failure : Int
  mut longest : Int
}

///|
fn build_failure_links(nodes : Array[Node], queue : Array[Int]) -> Unit {
  for index = 0; index < queue.length(); index = index + 1 {
    let state = queue[index]
    for unit, child in nodes[state].edges {
      let mut fallback = nodes[state].failure
      while fallback != 0 && !nodes[fallback].edges.contains(unit) {
        fallback = nodes[fallback].failure
      }
      let failure = nodes[fallback].edges.get(unit).unwrap_or(0)
      nodes[child].failure = failure
      nodes[child].longest = Int32::max(
        nodes[child].longest,
        nodes[failure].longest,
      )
      queue.push(child)
    }
  }
}
