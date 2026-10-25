///|
/// Validated graph and rule-independent scheduling data, computed once.
pub struct PreparedFunction {
  graph : Graph
  components : Array[Array[BlockId]]
  live_values : Array[Array[Bool]]
}

///|
pub suberror InvalidGraph {
  InvalidGraph(Array[String])
} derive(Debug)

///|
pub fn PreparedFunction::new(
  graph : Graph,
) -> PreparedFunction raise InvalidGraph {
  let errors = graph.validate()
  if !errors.is_empty() {
    raise InvalidGraph(errors)
  }
  { graph, components: graph.components(), live_values: graph.live_values(), }
}

///|
pub fn PreparedFunction::graph(self : PreparedFunction) -> Graph {
  self.graph
}

///|
pub fn PreparedFunction::components(
  self : PreparedFunction,
) -> Array[Array[BlockId]] {
  self.components
}

///|
pub fn PreparedFunction::live_values(
  self : PreparedFunction,
) -> Array[Array[Bool]] {
  self.live_values
}

///|
pub extend InvalidGraph with Debug::{to_repr}
