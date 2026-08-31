///|
priv struct MoongrepSkipAttributes {
  skip_structural : Bool
  invalid_payload_locations : Array[@basic.Location]
}

///|
fn impl_moongrep_skip_attributes(
  node : @untyped_cst.CstNode,
) -> MoongrepSkipAttributes {
  let mut skip_structural = false
  let invalid_payload_locations : Array[@basic.Location] = []
  for attr in @cst.attributes(node) {
    if attr.qualifier == Some("moongrep") && attr.name == "skip" {
      if attr.raw_payload == "" {
        skip_structural = true
      } else {
        invalid_payload_locations.push(attr.node.loc)
      }
    }
  }
  { skip_structural, invalid_payload_locations, }
}

///|
async fn scan_source_file(
  file : String,
  scan_plan : @rule_apply.ScanPlan,
  receive : async (ScanEvent) -> Unit,
) -> Unit {
  let source = read_text_file(file)
  let file_plan = scan_plan.filter_source(source)
  if file_plan.is_empty() {
    return
  }
  let source_lines = cache_source_lines(source)
  let blocks = split_source_blocks(source)
  let has_multiple_blocks = blocks.length() > 1
  for block in blocks {
    let block_plan = file_plan.filter_source(block.source)
    if block_plan.is_empty() {
      continue
    }
    let (impls, reports) = parse_source_block(block.source, file)
    if reports.length() > 0 {
      // A malformed matching block does not prevent other matching blocks in
      // the same file from being scanned.
      receive(
        Warning(
          Parse({
            file,
            block_start_line: if has_multiple_blocks {
              Some(block.start_line)
            } else {
              None
            },
            reason: "parse failed due to \{compact_scan_reports(reports)}",
          }),
        ),
      )
      continue
    }
    for node in impls {
      let skip = impl_moongrep_skip_attributes(node)
      for loc in skip.invalid_payload_locations {
        receive(
          Warning(InvalidMoongrepSkipPayload(file, block.rebase_location(loc))),
        )
      }
      if !skip.skip_structural {
        let structural_hits = @rule_apply.apply_structural_scan_plan_to_node(
          file, node, block_plan,
        )
        for finding in structural_hits {
          receive(
            Hit(make_scan_hit(source_lines, block.rebase_finding(finding))),
          )
        }
      }
      let taint_hits = @rule_apply.apply_taint_scan_plan_to_node(
        file, node, block_plan,
      )
      for finding in taint_hits {
        receive(Hit(make_scan_hit(source_lines, block.rebase_finding(finding))))
      }
    }
  }
}

///|
fn compact_scan_reports(reports : Array[@basic.Report]) -> String {
  let messages : Array[String] = []
  for report in reports {
    messages.push(report.msg.replace_all(old="\n", new=" "))
  }
  messages.join(" ")
}
