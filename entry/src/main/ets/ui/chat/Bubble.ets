/**
 * One chat bubble.
 *
 * The item is @ObjectLink, not a @Prop copy: a token delta mutates the observed
 * UiMessage in place and only this bubble redraws. v1 rebuilt the whole list per
 * frame, which is what made long generations stutter.
 *
 * Every colour, radius and font here is a token; none of them is a literal.
 */
import { AppColor, AppLine, AppRadius, AppSize, AppSpace, AppType, AppWidth } from '../../theme/Theme';
import { NoticeTone, UiKind, UiMessage } from '../../state/UiMessage';
import { QuoteKind } from '../../model/Attachment';
import { Parts } from '../../model/Parts';
import { humanBytes } from '../../core/Format';
import { Role } from '../../core/Wire';
import { Copy } from '../../l10n/Copy';
import { image } from '@kit.ImageKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { Markdown } from './Markdown';
import { MarkdownView } from './MarkdownView';

@Component
export struct Bubble {
  @ObjectLink item: UiMessage;
  onRecall: (key: string) => void = (): void => {};
  /** A ready image opens full-screen; the page owns that overlay, not this file. */
  onZoomImage: (key: string) => void = (): void => {};
  onToggleAudio: (key: string) => void = (): void => {};
  /** Long-press hands the bubble to the page, which owns the composer it fills. */
  onQuote: (item: UiMessage, kind: string) => void = (): void => {};
  /** A document opens in an app on the phone; the store fetches its bytes first. */
  onOpenFile: (item: UiMessage) => void = (): void => {};
  /** Bytes this phone already holds for one reference, read for the bubble's info line. */
  sizeOf: (ref: string) => number = (): number => 0;

  /**
   * A thought is worth reading while it is being written and rarely afterwards, so
   * the block follows the run: open while `streaming`, folded once the answer is
   * there. Two booleans instead of one because a tap has to override in both
   * directions — folding a live stream, reopening a turn from the history.
   */
  @State private thinkOverride: boolean = false;
  @State private thinkOpen: boolean = false;

  private thinkShown(): boolean {
    return this.thinkOverride ? this.thinkOpen : this.item.streaming;
  }

  private toggleThink(): void {
    this.thinkOpen = !this.thinkShown();
    this.thinkOverride = true;
  }

  /**
   * A tool card is the machinery behind an answer, not the answer: folded unless the
   * user asks for it. One boolean, not the reasoning block's pair — a tool call
   * arrives whole (the reducer never marks one streaming), so there is no run state
   * for a tap to override.
   */
  @State private toolOpen: boolean = false;

  private toggleTool(): void {
    this.toolOpen = !this.toolOpen;
  }

  private errorTone(): boolean {
    return this.item.tone === NoticeTone.ERROR;
  }

  private imageSource(): image.PixelMap | string {
    const value = this.item.image;
    if (value === undefined) {
      return '';
    }
    return value.map === undefined ? value.url : value.map;
  }

  private imageReady(): boolean {
    const value = this.item.image;
    return value !== undefined && !value.failed && !value.isEmpty();
  }

  private imageBroken(): boolean {
    const value = this.item.image;
    return value !== undefined && value.failed;
  }

  /** A Video reads a URL only: either the sandbox file or the server's own link. */
  private videoSource(): string {
    const value = this.item.video;
    return value === undefined ? '' : value.url;
  }

  /**
   * A `data:` URI is the bytes themselves, inlined in the transcript. Pointing a
   * new message at one would paste the whole payload into the request body, so
   * only stored paths and URLs come back out as quotes.
   */
  private quotable(ref: string): boolean {
    return ref.length > 0 && !ref.startsWith('data:');
  }

  private fileNameShown(): string {
    return this.item.fileName.length > 0
      ? Parts.leafOf(this.item.fileName) : Copy.chat_file_unavailable;
  }

  /**
   * Opening costs a round trip — the bytes live on the PC — so it is offered only
   * where there is a reference to fetch. A name with no reference is a file this
   * phone was told about but cannot reach, and a tap on it would fail every time.
   *
   * Neither does a `data:` document's: the reader is handed a file, and an inlined
   * payload carries no container suffix to name one by, so the tap would end in the
   * same failure the fetch path reports. Its bytes are still here, which is what the
   * info line says.
   */
  private openable(): boolean {
    return this.item.fileRef.length > 0 && !this.item.fileRef.startsWith('data:')
      && !this.item.fileBusy;
  }

  private viewCue(): string {
    return this.openable() ? Copy.chat_file_view : '';
  }

  /**
   * A bubble holding a table takes its width cap outright instead of sizing to its
   * content. The grid inside divides a percentage, and a percentage measures
   * against the page whenever the parent has no width of its own — that is how a
   * three-column table once grew straight out of its own bubble.
   */
  private bodyW(): ResourceStr {
    return Markdown.hasTable(this.item.text) ? AppWidth.bubble_max : 'auto';
  }

  private fileMeta(): string {
    if (this.item.fileBusy) {
      return Copy.chat_file_opening;
    }
    const ext = Parts.suffixOf(this.item.fileName);
    const kind = ext.length === 0
      ? Copy.chat_file_kind_unknown
      : Copy.fill(Copy.chat_file_kind, ext.toUpperCase());
    const ref = this.item.fileRef;
    // An inlined file's bytes are in the message itself, so no cache lookup can
    // find them and a miss would read "only on the PC" for a file already here.
    const size = ref.startsWith('data:') ? Parts.inlineBytes(ref) : this.sizeOf(ref);
    return Copy.fill2(Copy.chat_file_meta, kind,
      size > 0 ? Copy.fill(Copy.assets_local, humanBytes(size)) : Copy.assets_remote);
  }

  /**
   * The clipboard gets `item.text` as it stands — the markdown source the bubble
   * was rendered from, not the flattened picture of it. That is what makes the
   * paste "same format": headings, lists and tables arrive intact and re-render
   * wherever they land, instead of as a run-on paragraph.
   */
  private copyText(): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.item.text);
    pasteboard.getSystemPasteboard().setData(data)
      .then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: Copy.chat_copied });
      })
      .catch((): void => {
        this.getUIContext().getPromptAction().showToast({ message: Copy.chat_copy_failed });
      });
  }

  @Builder
  quoteItem(label: string, kind: string) {
    MenuItem({ content: label })
      .onClick((): void => {
        this.onQuote(this.item, kind);
      })
  }

  @Builder
  quoteMenu() {
    Menu() {
      if (this.item.text.length > 0) {
        MenuItem({ content: Copy.chat_copy_text })
          .onClick((): void => {
            this.copyText();
          })
        this.quoteItem(Copy.chat_quote_text, QuoteKind.TEXT)
      }
      if (this.quotable(this.item.imageRef)) {
        this.quoteItem(Copy.chat_quote_image, QuoteKind.IMAGE)
      }
      if (this.quotable(this.item.videoRef)) {
        this.quoteItem(Copy.chat_quote_video, QuoteKind.VIDEO)
      }
      if (this.quotable(this.item.audioRef)) {
        this.quoteItem(Copy.chat_quote_audio, QuoteKind.AUDIO)
      }
      if (this.quotable(this.item.fileRef)) {
        this.quoteItem(Copy.chat_quote_file, QuoteKind.FILE)
      }
    }
  }

  @Builder
  imageBlock() {
    if (this.imageReady()) {
      Image(this.imageSource())
        .objectFit(ImageFit.Contain)
        .borderRadius(AppRadius.card)
        .constraintSize({ maxWidth: AppWidth.bubble_max, maxHeight: AppSize.image_max })
        .onClick(() => {
          this.onZoomImage(this.item.key);
        })
        // A ready image is the whole bubble, and it eats the long press: without its
        // own binding the quote menu only opens on the few pixels of margin around it.
        .bindContextMenu(this.quoteMenu(), ResponseType.LongPress)
    } else if (this.imageBroken()) {
      Text(Copy.chat_image_unavailable)
        .fontSize(AppType.caption)
        .fontColor(AppColor.text_tertiary)
    } else {
      Text(Copy.chat_image_loading)
        .fontSize(AppType.caption)
        .fontColor(AppColor.text_tertiary)
    }
  }

  @Builder
  videoBlock() {
    if (this.videoSource().length > 0) {
      Video({ src: this.videoSource(), previewUri: '' })
        // Auto-play is the component's default, which in a scrolling list means a
        // clip starts sounding off the moment it scrolls into view.
        .autoPlay(false)
        .controls(true)
        .borderRadius(AppRadius.card)
        // Cover is the component's default, which cuts off whatever does not fit the
        // box; a clip's shape is only known once it plays, so contain it instead.
        .objectFit(ImageFit.Contain)
        // The box still gets a shape worth letterboxing into: 82% of a wide column
        // over a 220vp height is 2.5:1, mostly black around a 4:3 clip.
        .width(AppWidth.bubble_max)
        .constraintSize({ maxWidth: AppSize.video_max, maxHeight: AppSize.image_max })
        .bindContextMenu(this.quoteMenu(), ResponseType.LongPress)
    } else if (this.item.video !== undefined && this.item.video.failed) {
      Text(Copy.chat_video_unavailable)
        .fontSize(AppType.caption)
        .fontColor(AppColor.text_tertiary)
    } else {
      Text(Copy.chat_video_loading)
        .fontSize(AppType.caption)
        .fontColor(AppColor.text_tertiary)
    }
  }

  @Builder
  audioBlock(delivery: boolean) {
    if (this.item.audioRef.length > 0) {
      Row({ space: AppSpace.xxs }) {
        Text(this.item.audioPlaying ? Copy.chat_audio_playing : Copy.chat_audio_label)
          .fontSize(AppType.caption)
          .fontColor(this.item.audioPlaying ? AppColor.accent_text : AppColor.text_secondary)
      }
      // The fill still marks playing and nothing else; a delivery only adds the
      // outline, so the one state cue the pill has is not diluted by the other.
      .backgroundColor(this.item.audioPlaying ? AppColor.accent_soft : AppColor.surface_subtle)
      .border(delivery ? { width: AppLine.emphasis, color: AppColor.accent_action }
        : { width: 0, color: AppColor.border_subtle })
      .padding(AppSpace.sm)
      .borderRadius(AppRadius.card)
      .constraintSize({ maxWidth: AppWidth.bubble_max })
      .onClick(() => {
        this.onToggleAudio(this.item.key);
      })
      .bindContextMenu(this.quoteMenu(), ResponseType.LongPress)
    }
  }

  @Builder
  fileBlock(delivery: boolean) {
    if (this.item.fileRef.length > 0 || this.item.fileName.length > 0) {
      Column({ space: AppSpace.xxs }) {
        Text(`📄 ${this.fileNameShown()}`)
          .fontSize(AppType.caption)
          .fontWeight(delivery ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(delivery ? AppColor.accent_text : AppColor.text_secondary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: AppSpace.xxs }) {
          // No layoutWeight() and no Blank(): either one lets the info line take the
          // whole row, and the cue after it is then laid out past the card's edge and
          // clipped — it measured to nothing on the emulator.
          Text(this.fileMeta())
            .fontSize(AppType.caption)
            .fontColor(AppColor.text_quaternary)
          Text(this.viewCue())
            .fontSize(AppType.caption)
            .fontColor(AppColor.accent_text)
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      // A file the PC handed over is the thing the user asked for, and it has to be
      // picked out of a screen full of folded cards; the outgoing receipt of a file
      // the user sent themselves is not, so only the incoming one takes the accent.
      .backgroundColor(delivery ? AppColor.accent_soft : AppColor.surface_subtle)
      .border(delivery ? { width: AppLine.emphasis, color: AppColor.accent_action }
        : { width: AppLine.thin, color: AppColor.border_subtle })
      .padding(AppSpace.sm)
      .borderRadius(AppRadius.card)
      .constraintSize({ maxWidth: AppWidth.bubble_max })
      .onClick(() => {
        if (this.openable()) {
          this.onOpenFile(this.item);
        }
      })
      // Same reason the image carries its own binding: the card fills the bubble, so
      // without it「引用这个文件」would only open on the padding under the name.
      .bindContextMenu(this.quoteMenu(), ResponseType.LongPress)
    }
  }

  /**
   * The media a bubble carries, in the order the turn produced them. Answer text and
   * a tool card both sit under it, because a file is the part the user asked for and
   * the words about it are the commentary.
   *
   * Only the receiving bubbles use this: what the user sent goes out through the
   * user-side branch below, where the same cards are drawn as receipts.
   */
  @Builder
  assetBlocks() {
    if (this.item.imageRef.length > 0) {
      this.imageBlock()
    }
    if (this.item.videoRef.length > 0) {
      this.videoBlock()
    }
    if (this.item.audioRef.length > 0) {
      this.audioBlock(true)
    }
    if (this.item.fileRef.length > 0 || this.item.fileName.length > 0) {
      this.fileBlock(true)
    }
  }

  build() {
    if (this.item.kind === UiKind.NOTICE) {
      Row() {
        Text(this.item.text)
          .fontSize(AppType.caption)
          .fontColor(this.errorTone() ? AppColor.error_text : AppColor.text_tertiary)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.item.kind === UiKind.QUEUED) {
      Column({ space: AppSpace.xxs }) {
        Text(this.item.text)
          .fontSize(AppType.message)
          .fontColor(AppColor.accent_text)
          .backgroundColor(AppColor.accent_soft)
          .padding(AppSpace.sm)
          .borderRadius(AppRadius.card)
          .constraintSize({ maxWidth: AppWidth.bubble_max })
        Text(Copy.chat_queued_hint)
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_tertiary)
      }
      .alignItems(HorizontalAlign.End)
      .width('100%')
      .onClick(() => {
        this.onRecall(this.item.key);
      })
    } else if (this.item.role === Role.USER) {
      Column({ space: AppSpace.xxs }) {
        if (this.item.imageRef.length > 0) {
          this.imageBlock()
        }
        if (this.item.videoRef.length > 0) {
          this.videoBlock()
        }
        if (this.item.audioRef.length > 0) {
          this.audioBlock(false)
        }
        if (this.item.fileRef.length > 0 || this.item.fileName.length > 0) {
          this.fileBlock(false)
        }
        if (this.item.text.length > 0) {
          // The composer's own quote feature writes markdown (`> ` lines), and a
          // plain Text would show the user the markup instead of the quote. The tint
          // is what keeps the answer's colours out of the sender's bubble, and the
          // fill is a tint rather than the brand orange so this ink clears 4.5:1.
          Column() {
            MarkdownView({ src: this.item.text, tint: AppColor.text })
          }
          .alignItems(HorizontalAlign.Start)
          .backgroundColor(AppColor.bubble_mine)
          .border({ width: AppLine.thin, color: AppColor.bubble_mine_border })
          .padding(AppSpace.sm)
          .borderRadius(AppRadius.card)
          .width(this.bodyW())
          .constraintSize({ maxWidth: AppWidth.bubble_max })
        }
        if (this.item.undelivered) {
          // Kept on screen after the history rebuild that follows a rejected send,
          // so the text the server refused is still here to quote and re-send.
          Text(Copy.chat_undelivered)
            .fontSize(AppType.caption)
            .fontColor(AppColor.error_text)
        }
      }
      .alignItems(HorizontalAlign.End)
      .width('100%')
      .bindContextMenu(this.quoteMenu(), ResponseType.LongPress)
    } else if (this.item.kind === UiKind.TOOL) {
      Column({ space: AppSpace.xxs }) {
        // A tool that handed over a file carries it here, above its own card: the
        // card folds by default, and a file the user asked for is not something to
        // dig out of a fold.
        this.assetBlocks()
        Column({ space: AppSpace.xxs }) {
          Row({ space: AppSpace.xxs }) {
            // A card that delivered a document is titled by that document: a run of
            // them all read `🔧 send_file_to_user`, which is not something to scan a
            // screen for. The tool's name goes one line below instead of into the
            // fold, so the title swaps what it leads with and loses nothing.
            Text(this.item.fileName.length > 0
              ? Copy.fill(Copy.chat_tool_delivery, this.fileNameShown())
              : Copy.fill(Copy.chat_tool_label, this.item.name))
              .fontSize(AppType.caption)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.item.fileName.length > 0
                ? AppColor.accent_text : AppColor.warning_text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(this.toolOpen ? Copy.chat_tool_collapse : Copy.chat_tool_expand)
              .fontSize(AppType.caption)
              .fontColor(AppColor.warning_text)
          }
          .width('100%')
          .onClick((): void => {
            this.toggleTool();
          })
          if (this.item.fileName.length > 0) {
            Text(Copy.fill(Copy.chat_tool_label, this.item.name))
              .fontSize(AppType.caption)
              .fontColor(AppColor.warning_text)
          }
          if (this.toolOpen) {
            // No line cap: the text was already clipped when it was read off the wire,
            // and a fold the user just opened should show what it holds.
            Text(this.item.text)
              .fontSize(AppType.caption)
              .fontColor(AppColor.warning_text)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .backgroundColor(AppColor.warning_bg)
        .border({ width: AppLine.thin, color: AppColor.warning_border })
        .padding(AppSpace.sm)
        .borderRadius(AppRadius.card)
        .constraintSize({ maxWidth: AppWidth.tool_max })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    } else if (this.item.kind === UiKind.REASONING) {
      Column({ space: AppSpace.xxs }) {
        Row({ space: AppSpace.xxs }) {
          Text(Copy.chat_reasoning_label)
            .fontSize(AppType.caption)
            .fontColor(AppColor.text_tertiary)
          Blank()
          Text(this.thinkShown() ? Copy.chat_reasoning_collapse : Copy.chat_reasoning_expand)
            .fontSize(AppType.caption)
            .fontColor(AppColor.text_tertiary)
        }
        .width('100%')
        .onClick((): void => {
          this.toggleThink();
        })
        if (this.thinkShown()) {
          Text(this.item.text)
            .fontSize(AppType.caption)
            .fontStyle(FontStyle.Italic)
            .fontColor(AppColor.text_secondary)
            .maxLines(6)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(AppColor.surface_subtle)
      .padding(AppSpace.sm)
      .borderRadius(AppRadius.card)
      .constraintSize({ maxWidth: AppWidth.tool_max })
    } else {
      Column({ space: AppSpace.xxs }) {
        this.assetBlocks()
        if (this.item.text.length > 0) {
          Column() {
            MarkdownView({ src: this.item.text, streaming: this.item.streaming })
          }
          .alignItems(HorizontalAlign.Start)
          .backgroundColor(AppColor.surface)
          .padding(AppSpace.sm)
          .borderRadius(AppRadius.card)
          .border({ width: AppLine.thin, color: AppColor.border_subtle })
          .width(this.bodyW())
          .constraintSize({ maxWidth: AppWidth.bubble_max })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .bindContextMenu(this.quoteMenu(), ResponseType.LongPress)
    }
  }
}
