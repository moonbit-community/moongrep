#moongrep.skip
fn skipped_structural {
  target()
}

fn unskipped_structural {
  target()
}

#moongrep.skip
fn skipped_taint {
  let x = get_user_input()
  sink(x)
}
