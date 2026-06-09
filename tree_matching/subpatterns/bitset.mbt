///|
/// Mutable bitset used for match sets.
///
/// Bit `0` is reserved for the distinguished wildcard subpattern `v` from the
/// paper. Bits `1..` correspond to deduplicated non-wildcard pattern subtrees.
/// The matcher mutates temporary bitsets heavily while computing intersections
/// and unions, so this package uses `Array[UInt64]` directly instead of a more
/// abstract collection.
priv struct Bitset {
  words : Array[UInt64]
}

///|
/// Return the number of 64-bit words needed to store `bit_count` bits.
fn bitset_word_count(bit_count : Int) -> Int {
  (bit_count + 63) / 64
}

///|
/// Allocate an all-zero bitset.
fn Bitset::new(word_count : Int) -> Bitset {
  { words: Array::make(word_count, 0UL) }
}

///|
/// Copy the backing words before destructive set operations.
fn Bitset::copy(self : Bitset) -> Bitset {
  { words: self.words.copy() }
}

///|
/// Set a bit in place.
fn Bitset::set(self : Bitset, bit : Int) -> Unit {
  let word_index = bit / 64
  let offset = bit % 64
  self.words[word_index] = self.words[word_index] | (1UL << offset)
}

///|
/// Union `other` into `self`.
fn Bitset::union_in_place(self : Bitset, other : Bitset) -> Unit {
  for i in 0..<self.words.length() {
    self.words[i] = self.words[i] | other.words[i]
  }
}

///|
/// Intersect `self` with `other`.
fn Bitset::intersect_in_place(self : Bitset, other : Bitset) -> Unit {
  for i in 0..<self.words.length() {
    self.words[i] = self.words[i] & other.words[i]
  }
}

///|
/// Iterate set bits from low to high.
///
/// The `word & (word - 1)` step clears the lowest set bit within each word;
/// the outer loop still scans every backing word, while the inner loop is
/// proportional to the number of set bits.
fn Bitset::each_set_bit(
  self : Bitset,
  handle : (Int) -> Unit raise?,
) -> Unit raise? {
  for word_index in 0..<self.words.length() {
    let mut word = self.words[word_index]
    while word != 0UL {
      let offset = word.ctz()
      handle(word_index * 64 + offset)
      word = word & (word - 1UL)
    }
  }
}
