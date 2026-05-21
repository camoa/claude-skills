/**
 * SlidesClient — the typed transport surface over the Google Slides + Drive
 * REST APIs.
 *
 * It depends on injected `googleapis` service objects (the DIP seam from
 * architecture.md) so unit tests pass fakes and never hit the network. Every
 * call is wrapped in {@link withRetry}. Errors propagate raw — `cli.ts`
 * normalizes them at the process boundary via `errors.ts`.
 */
import type { slides_v1 } from 'googleapis';
import type {
  SlidesServices,
  TagMap,
  ExportMimeType,
  CreatePresentationResult,
  BatchUpdateResult,
  CopyFileResult,
  ThumbnailResult,
  ReplaceResult,
} from './types.js';
import {
  buildReplaceAllTextRequests,
  buildReplaceAllShapesWithImageRequests,
} from './requests.js';
import { Readable } from 'node:stream';
import { withRetry, type RetryOptions } from './retry.js';

export class SlidesClient {
  constructor(
    private readonly services: SlidesServices,
    private readonly retry: RetryOptions = {},
  ) {}

  /** Create a blank presentation; returns its id. */
  async createPresentation(title: string): Promise<CreatePresentationResult> {
    const res = await withRetry(
      () => this.services.slides.presentations.create({ requestBody: { title } }),
      this.retry,
    );
    const presentationId = res.data.presentationId;
    if (!presentationId) {
      throw new Error('Slides API returned no presentationId');
    }
    return { presentationId };
  }

  /** Fetch a full presentation resource. */
  async getPresentation(
    presentationId: string,
  ): Promise<slides_v1.Schema$Presentation> {
    const res = await withRetry(
      () => this.services.slides.presentations.get({ presentationId }),
      this.retry,
    );
    return res.data;
  }

  /**
   * Apply an atomic `batchUpdate`. The raw request array is passed straight
   * through, preserving full Slides API coverage. The batch is atomic — if the
   * API rejects it, nothing was applied and the rejection propagates.
   */
  async batchUpdate(
    presentationId: string,
    requests: slides_v1.Schema$Request[],
  ): Promise<BatchUpdateResult> {
    const res = await withRetry(
      () =>
        this.services.slides.presentations.batchUpdate({
          presentationId,
          requestBody: { requests },
        }),
      this.retry,
    );
    return { replies: res.data.replies ?? [] };
  }

  /** Duplicate a Drive file (the template-copy step); returns the new id. */
  async copyFile(
    fileId: string,
    newName: string,
    parentId?: string,
  ): Promise<CopyFileResult> {
    const res = await withRetry(
      () =>
        this.services.drive.files.copy({
          fileId,
          requestBody: {
            name: newName,
            ...(parentId ? { parents: [parentId] } : {}),
          },
        }),
      this.retry,
    );
    const id = res.data.id;
    if (!id) {
      throw new Error('Drive API returned no file id for the copy');
    }
    return { fileId: id };
  }

  /** Export a file (PDF or PNG) via the Drive API; returns the bytes. */
  async exportFile(fileId: string, mimeType: ExportMimeType): Promise<Buffer> {
    const res = await withRetry(
      () =>
        this.services.drive.files.export(
          { fileId, mimeType },
          { responseType: 'arraybuffer' },
        ),
      this.retry,
    );
    return Buffer.from(res.data as ArrayBuffer);
  }

  /**
   * Upload an image to Drive, make it readable by anyone with the link, and
   * return a URL the Slides API can fetch — for `createImage` /
   * `replaceAllShapesWithImage`, which require a publicly reachable URL.
   *
   * The scaffolder uses this to host baked gradient/display-text images.
   * NOTE: whether the Slides API's server-side fetch can read this URL is the
   * epic's flagged image-reachability item — verify via the live spike.
   */
  async uploadImage(
    name: string,
    bytes: Buffer,
    mimeType = 'image/png',
  ): Promise<{ fileId: string; url: string }> {
    const created = await withRetry(
      () =>
        this.services.drive.files.create({
          requestBody: { name },
          media: { mimeType, body: Readable.from(bytes) },
          fields: 'id',
        }),
      this.retry,
    );
    const fileId = created.data.id;
    if (!fileId) {
      throw new Error('Drive API returned no file id for the uploaded image');
    }
    await withRetry(
      () =>
        this.services.drive.permissions.create({
          fileId,
          requestBody: { role: 'reader', type: 'anyone' },
        }),
      this.retry,
    );
    return {
      fileId,
      url: `https://drive.google.com/uc?export=view&id=${fileId}`,
    };
  }

  /** Get a single page's PNG thumbnail URL (feeds the visual-diff gate). */
  async getPageThumbnail(
    presentationId: string,
    pageObjectId: string,
  ): Promise<ThumbnailResult> {
    const res = await withRetry(
      () =>
        this.services.slides.presentations.pages.getThumbnail({
          presentationId,
          pageObjectId,
        }),
      this.retry,
    );
    const contentUrl = res.data.contentUrl;
    if (!contentUrl) {
      throw new Error('Slides API returned no thumbnail contentUrl');
    }
    return { contentUrl };
  }

  /**
   * Tag-map helper: replace each tag's literal text. When `pageObjectIds` is
   * given the replacement is scoped to those pages only — required to fill a
   * specific instance of a repeated slide type, or a slide's notes page.
   */
  async replaceAllText(
    presentationId: string,
    tagMap: TagMap,
    pageObjectIds?: string[],
  ): Promise<ReplaceResult> {
    return this.applyReplacements(
      presentationId,
      tagMap,
      buildReplaceAllTextRequests(tagMap, pageObjectIds),
    );
  }

  /**
   * Tag-map helper: replace each tagged placeholder shape with an image.
   * `pageObjectIds`, when given, scopes the replacement to those pages only.
   */
  async replaceAllShapesWithImage(
    presentationId: string,
    tagImageMap: TagMap,
    pageObjectIds?: string[],
  ): Promise<ReplaceResult> {
    return this.applyReplacements(
      presentationId,
      tagImageMap,
      buildReplaceAllShapesWithImageRequests(tagImageMap, pageObjectIds),
    );
  }

  /**
   * Run a positional set of replace requests and map each reply's
   * `occurrencesChanged` back to its tag (requests and replies are positional).
   */
  private async applyReplacements(
    presentationId: string,
    tagMap: TagMap,
    requests: slides_v1.Schema$Request[],
  ): Promise<ReplaceResult> {
    const tags = Object.keys(tagMap);
    const occurrencesByTag: Record<string, number> = {};
    for (const tag of tags) {
      occurrencesByTag[tag] = 0;
    }
    if (requests.length === 0) {
      return { occurrencesByTag };
    }
    // Slides returns one reply per request, positionally — map each back to
    // its tag by index. A short reply array leaves trailing tags at 0.
    const { replies } = await this.batchUpdate(presentationId, requests);
    replies.forEach((reply, i) => {
      const tag = tags[i];
      if (tag === undefined) return;
      occurrencesByTag[tag] =
        reply.replaceAllText?.occurrencesChanged ??
        reply.replaceAllShapesWithImage?.occurrencesChanged ??
        0;
    });
    return { occurrencesByTag };
  }
}
