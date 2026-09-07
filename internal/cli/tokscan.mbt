///|
/// Searches consecutive tokens within source blocks and streams every match.
/// Exclusions use scan's recursive entry rules; explicit roots are still scanned.
/// JSON mode writes findings to stdout and lexical warnings to stderr.
pub async fn run_tokscan_command(
  patterns : Array[String],
  scan_root~ : String,
  no_color~ : Bool,
  excludes? : Array[String] = [],
  output_json? : Bool = false,
) -> Unit {
  run_tokscan_with_writers(
    patterns,
    scan_root,
    no_color,
    write_scan_stdout,
    write_scan_stderr,
    excludes~,
    output_json~,
  )
}

///|
async fn run_tokscan_with_writers(
  sources : Array[String],
  scan_root : String,
  no_color : Bool,
  stdout_writer : async (String) -> Unit,
  stderr_writer : async (String) -> Unit,
  excludes? : Array[String] = [],
  output_json? : Bool = false,
) -> Unit {
  // Validate all patterns before accessing the root or emitting any matches.
  let sources = sources.copy()
  let matcher = prepare_tokscan_patterns(sources)
  let state : ScanOutputState = { hit_count: 0, }
  visit_source_files(
    normalize_scan_root(scan_root),
    normalize_scan_excludes(excludes),
    file => {
      let source = read_text_file(file)
      let source_lines = cache_source_lines(source)
      let blocks = split_source_blocks(source)
      for block in blocks {
        let hits = matcher.find_matches(block.source, name=file) catch {
          @tokmatch.LexError(reason) => {
            let warning : ParseWarning = {
              file,
              block_start_line: if blocks.length() > 1 {
                Some(block.start_line)
              } else {
                None
              },
              reason: "lexing failed: \{reason}",
            }
            let rendered = if output_json {
              render_source_warning_json(warning, category="lexical")
            } else {
              render_scan_warning(Parse(warning))
            }
            invoke_scan_writer(stderr_writer, rendered + "\n")
            continue
          }
        }
        for hit in hits {
          let loc = block.rebase_location(hit.loc)
          let rendered = if output_json {
            render_tokscan_hit_json(
              file,
              loc,
              sources[hit.pattern_index],
              source_lines,
            )
          } else {
            render_tokscan_hit(
              file,
              loc,
              sources[hit.pattern_index],
              source_lines,
              no_color~,
            )
          }
          let separator = if !output_json && state.hit_count > 0 {
            "\n"
          } else {
            ""
          }
          invoke_scan_writer(stdout_writer, separator + rendered + "\n")
          state.hit_count += 1
        }
      }
    },
    _ => (),
  )
  if !output_json && state.hit_count == 0 {
    invoke_scan_writer(stdout_writer, "no match hits\n")
  }
}

///|
fn render_tokscan_hit(
  file : String,
  loc : @basic.Location,
  pattern : String,
  source_lines : SourceLines,
  no_color~ : Bool,
) -> String {
  let lines = [format_location(file, loc), "pattern:"]
  for line in pattern.split("\n") {
    lines.push("  \{line}")
  }
  lines.push("source:")
  lines.append(
    render_source_context(
      source_context_for_location(source_lines, loc),
      loc,
      no_color~,
    ),
  )
  lines.join("\n")
}
