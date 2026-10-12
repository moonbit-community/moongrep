fn sample {
  guard ready() else { fallback() }
  continue_work()
}
