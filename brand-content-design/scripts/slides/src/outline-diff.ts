/**
 * Pure diff between a prior {@link RenderManifest} and a new payload — the
 * planning surface the resync engine consults before touching the deck.
 *
 * Position is the join key. `slides[i]` in the prior manifest is compared
 * against `payload[i]` in the new payload. A type mismatch at the same index
 * counts as `removed` (prior) + `added` (new) — the resync rebuild treats
 * both as structural ops.
 */
import type { RenderManifest, ManifestSlide } from './render-manifest.js';
import type { ContentSlide, ContentPayload } from './payload-validator.js';

/** One slide present in both prior and new, unchanged in every recorded field. */
export interface UnchangedSlide {
  index: number;
  type: string;
}

/**
 * One slide whose `type` is unchanged but whose text/images/speakerNotes
 * differ. `changedFields` lists every key whose value moved (text and image
 * tags share a namespace as far as the diff is concerned; `speakerNotes` is
 * reported under that literal key).
 */
export interface RefilledSlide {
  index: number;
  type: string;
  changedFields: string[];
}

/** A slide present in `next` at this index but not at the same index in `prev`. */
export interface AddedSlide {
  index: number;
  type: string;
}

/** A slide present in `prev` at this index but not at the same index in `next`. */
export interface RemovedSlide {
  prevIndex: number;
  type: string;
}

/** The full diff report. */
export interface OutlineDiff {
  unchanged: UnchangedSlide[];
  refilled: RefilledSlide[];
  added: AddedSlide[];
  removed: RemovedSlide[];
  /**
   * True when the new payload's slide `type` sequence is a non-trivial
   * reordering of the prior manifest's sequence (same multiset of types, but
   * different order). False when the types are identical-positional or when
   * the change is purely add/remove. Cheap heuristic — the resync engine
   * doesn't act on this differently in v1.
   */
  reordered: boolean;
}

/**
 * Compute the per-index diff between the prior manifest's slides and the new
 * payload. The result is empty (every list `[]`, `reordered: false`) iff
 * re-rendering the new payload would yield byte-equivalent output to the
 * prior render — the resync engine's no-op fast path.
 */
export function diffOutline(
  prev: RenderManifest,
  next: ContentPayload,
): OutlineDiff {
  const unchanged: UnchangedSlide[] = [];
  const refilled: RefilledSlide[] = [];
  const added: AddedSlide[] = [];
  const removed: RemovedSlide[] = [];

  const longest = Math.max(prev.slides.length, next.length);
  for (let i = 0; i < longest; i++) {
    const p = prev.slides[i];
    const n = next[i];
    if (p && !n) {
      removed.push({ prevIndex: i, type: p.type });
      continue;
    }
    if (n && !p) {
      added.push({ index: i, type: n.type });
      continue;
    }
    if (!p || !n) continue; // unreachable but narrows types

    if (p.type !== n.type) {
      removed.push({ prevIndex: i, type: p.type });
      added.push({ index: i, type: n.type });
      continue;
    }

    const changed = changedFieldsOf(p, n);
    if (changed.length === 0) {
      unchanged.push({ index: i, type: p.type });
    } else {
      refilled.push({ index: i, type: p.type, changedFields: changed });
    }
  }

  return {
    unchanged,
    refilled,
    added,
    removed,
    reordered: detectReordered(prev.slides, next),
  };
}

/** Compare a prior {@link ManifestSlide} to a new {@link ContentSlide}. */
function changedFieldsOf(prev: ManifestSlide, next: ContentSlide): string[] {
  const out: string[] = [];
  const nextText = next.text ?? {};
  const nextImages = next.images ?? {};

  for (const key of unionKeys(prev.text, nextText)) {
    if (prev.text[key] !== nextText[key]) out.push(key);
  }
  for (const key of unionKeys(prev.images, nextImages)) {
    if (prev.images[key] !== nextImages[key]) out.push(key);
  }
  const prevNotes = prev.speakerNotes ?? '';
  const nextNotes = next.speakerNotes ?? '';
  if (prevNotes !== nextNotes) out.push('speakerNotes');

  return out;
}

function unionKeys(
  a: Record<string, string>,
  b: Record<string, string>,
): string[] {
  return Array.from(new Set([...Object.keys(a), ...Object.keys(b)]));
}

/**
 * `true` when the two type sequences are the same multiset but a different
 * permutation. Same-positional or differing-multiset → `false`.
 */
function detectReordered(prev: ManifestSlide[], next: ContentPayload): boolean {
  if (prev.length !== next.length) return false;
  let samePositional = true;
  for (let i = 0; i < prev.length; i++) {
    if (prev[i].type !== next[i].type) {
      samePositional = false;
      break;
    }
  }
  if (samePositional) return false;

  const prevSorted = prev.map((s) => s.type).sort();
  const nextSorted = next.map((s) => s.type).sort();
  for (let i = 0; i < prevSorted.length; i++) {
    if (prevSorted[i] !== nextSorted[i]) return false;
  }
  return true;
}

/** True iff the diff is the no-op fast path — nothing to do. */
export function isEmptyDiff(diff: OutlineDiff): boolean {
  return (
    diff.refilled.length === 0 &&
    diff.added.length === 0 &&
    diff.removed.length === 0
  );
}
