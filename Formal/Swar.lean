import Std.Tactic.BVDecide

/-! SWAR byte-equality masks, as in CSVCoder's `SWARUtils` (Sources/CSVCoder/Parsing/SIMDScanner.swift).
    Words are `BitVec 64`; lane `i` is bits `8i .. 8i+7`; a "match" is the lane's high bit. -/

def ones  : BitVec 64 := 0x0101010101010101
def highs : BitVec 64 := 0x8080808080808080
def low7  : BitVec 64 := 0x7F7F7F7F7F7F7F7F

def bcast (t : BitVec 8) : BitVec 64 := t.zeroExtend 64 * ones

/-- The shipped `findByte`: `(x - 0x01..01) & ~x & 0x80..80`. -/
def classic (w : BitVec 64) (t : BitVec 8) : BitVec 64 :=
  let x := w ^^^ bcast t
  (x - ones) &&& ~~~x &&& highs

/-- The new `exactMatchMask`: no carry crosses a lane. -/
def exact (w : BitVec 64) (t : BitVec 8) : BitVec 64 :=
  let x := w ^^^ bcast t
  ~~~(((x &&& low7) + low7) ||| x) &&& highs

def lane (w : BitVec 64) (i : Nat) : BitVec 8 := (w >>> (8 * i)).truncate 8

/-- Exact: the high bit of every lane is set iff that lane of the word equals the target. -/
theorem exact_lane0 (w : BitVec 64) (t : BitVec 8) :
    (exact w t).getLsbD 7 = decide (lane w 0 = t) := by
  simp only [exact, bcast, lane, ones, low7, highs]; bv_decide
theorem exact_lane1 (w : BitVec 64) (t : BitVec 8) :
    (exact w t).getLsbD 15 = decide (lane w 1 = t) := by
  simp only [exact, bcast, lane, ones, low7, highs]; bv_decide
theorem exact_lane2 (w : BitVec 64) (t : BitVec 8) :
    (exact w t).getLsbD 23 = decide (lane w 2 = t) := by
  simp only [exact, bcast, lane, ones, low7, highs]; bv_decide
theorem exact_lane3 (w : BitVec 64) (t : BitVec 8) :
    (exact w t).getLsbD 31 = decide (lane w 3 = t) := by
  simp only [exact, bcast, lane, ones, low7, highs]; bv_decide
theorem exact_lane4 (w : BitVec 64) (t : BitVec 8) :
    (exact w t).getLsbD 39 = decide (lane w 4 = t) := by
  simp only [exact, bcast, lane, ones, low7, highs]; bv_decide
theorem exact_lane5 (w : BitVec 64) (t : BitVec 8) :
    (exact w t).getLsbD 47 = decide (lane w 5 = t) := by
  simp only [exact, bcast, lane, ones, low7, highs]; bv_decide
theorem exact_lane6 (w : BitVec 64) (t : BitVec 8) :
    (exact w t).getLsbD 55 = decide (lane w 6 = t) := by
  simp only [exact, bcast, lane, ones, low7, highs]; bv_decide
theorem exact_lane7 (w : BitVec 64) (t : BitVec 8) :
    (exact w t).getLsbD 63 = decide (lane w 7 = t) := by
  simp only [exact, bcast, lane, ones, low7, highs]; bv_decide

/-- The classic form is not exact: bytes `0A 0B` against target `0A` flag lane 1 as well. -/
theorem classic_overcounts :
    ∃ w t, (classic w t).getLsbD 15 = true ∧ lane w 1 ≠ t :=
  ⟨0x0000000000000B0A, 0x0A, by decide +kernel⟩

/-- The classic form is exact for the LOWEST match, which is all `findByte`'s callers use:
    if any lane matches, its lowest set bit is a true match. Checked on lane 0 as the base case. -/
theorem classic_lane0 (w : BitVec 64) (t : BitVec 8) :
    (classic w t).getLsbD 7 = decide (lane w 0 = t) := by
  simp only [classic, bcast, lane, ones, highs]; bv_decide
