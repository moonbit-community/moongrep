///|
fn single_case_variants(value : Event) -> Unit {
  match value {
    Ready => start()
    _ => ()
  }
  match next_event() {
    @events.Event::Payload(value=Some(inner), ..) => {
      prepare(inner)
      consume(inner)
    }
    _ => { () }
  }
  match value {
    Payload(inner, _) => consume(inner)
    _ => { () }
  }
  match value {
    Payload(inner, _) if valid(inner) => consume(inner)
    _ => ()
  }
  match value {
    Payload(inner, _) => consume(inner)
    _ => { log(); () }
  }
  match value {
    Ready => start()
    Payload(inner, _) => consume(inner)
    _ => ()
  }
  match value {
    Payload(inner, _) as whole => consume(whole)
    _ => ()
  }
  match value {
    Ready | Done => finish()
    _ => ()
  }
}

///|
fn empty_map_fallback(value : Int?) -> Map[Int, Int] {
  match value {
    Some(inner) => { 0: inner }
    _ => {}
  }
}
