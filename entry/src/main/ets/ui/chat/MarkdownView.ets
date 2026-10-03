/**
 * Markdown blocks rendered as one chat bubble body.
 *
 * Parsing is memoised on the source string plus the streaming flag. A streaming
 * reply rewrites the whole text on every frame, and without the cache a long answer
 * would re-tokenise itself hundreds of times per message; with it, only the block
 * that grew is rebuilt, because the ForEach key carries that block's own length.
 * The flag is part of the key because the caret is baked into the cached blocks: a
 * run that ends without changing the text has to drop it.
 *
 * The bubble's own background, padding and border stay in Bubble: this component
 * only ever sizes to its content, so a short reply is still a short bubble.
 */
import { AppColor, AppFont, AppLine, AppRadius, AppSpace, AppType } from '../../theme/Theme';
import { MdBlock, MdKind, MdRun, Markdown } from './Markdown';

@Component
export struct MarkdownView {
  @Prop src: string = '';
  @Prop streaming: boolean = false;
  bodySize: Resource = AppType.message;
  tint: Resource = AppColor.text;
  private blocks: MdBlock[] = [];
  private parsedSrc: string = '\u0000';
  private parsedLive: boolean = false;

  private model(): MdBlock[] {
    if (this.parsedSrc !== this.src || this.parsedLive !== this.streaming) {
      this.parsedSrc = this.src;
      this.parsedLive = this.streaming;
      this.blocks = Markdown.parse(this.src);
      if (this.streaming) {
        this.addCaret();
      }
    }
    return this.blocks;
  }

  private addCaret(): void {
    if (this.blocks.length === 0) {
      return;
    }
    const last: MdBlock = this.blocks[this.blocks.length - 1];
    if (last.kind === MdKind.code) {
      const at: number = last.lines.length - 1;
      last.lines[at] = at < 0 ? '▍' : `${last.lines[at]} ▍`;
      return;
    }
    const run = new MdRun();
    run.text = ' ▍';
    last.runs.push(run);
  }

  /**
   * A block's own text length is part of its key on purpose: without it a growing
   * stream keeps the same key and ForEach hands back the stale child.
   */
  private sig(block: MdBlock, index: number): string {
    let n: number = 0;
    for (let i = 0; i < block.runs.length; i++) {
      n += block.runs[i].text.length;
    }
    for (let i = 0; i < block.lines.length; i++) {
      n += block.lines[i].length;
    }
    return `${index}:${block.kind}:${block.depth}:${block.marker}:${n}`;
  }

  private headSize(block: MdBlock): Resource {
    if (block.depth === 1) {
      return AppType.title;
    }
    return block.depth === 2 ? AppType.subtitle : this.bodySize;
  }

  @Builder
  runs(block: MdBlock, size: Resource, forceBold: boolean) {
    Text() {
      ForEach(block.runs, (run: MdRun) => {
        if (run.code) {
          Span(run.text)
            .fontFamily(AppFont.mono)
            .fontSize(size)
            .fontColor(AppColor.accent_text)
        } else if (run.link) {
          Span(run.text)
            .fontSize(size)
            .fontColor(AppColor.accent_active)
            .decoration({ type: TextDecorationType.Underline, color: AppColor.accent_active })
        } else {
          Span(run.text)
            .fontSize(size)
            .fontWeight(run.bold || forceBold ? FontWeight.Bold : FontWeight.Normal)
            .fontStyle(run.italic ? FontStyle.Italic : FontStyle.Normal)
            .decoration({
              type: run.strike ? TextDecorationType.LineThrough : TextDecorationType.None,
              color: this.tint
            })
        }
      }, (run: MdRun, index: number) => `${index}:${run.text}`)
    }
    .fontSize(size)
    .fontColor(this.tint)
  }

  @Builder
  codeBlock(block: MdBlock) {
    Text(block.lines.join('\n'))
      .fontSize(AppType.secondary)
      .fontFamily(AppFont.mono)
      .fontColor(this.tint)
      .backgroundColor(AppColor.surface_sunken)
      .border({ width: AppLine.thin, color: AppColor.border_subtle })
      .borderRadius(AppRadius.control)
      .padding(AppSpace.sm)
      .copyOption(CopyOptions.LocalDevice)
  }

  @Builder
  listBlock(block: MdBlock) {
    Row({ space: AppSpace.xs }) {
      Text(block.marker)
        .fontSize(this.bodySize)
        .fontColor(AppColor.text_tertiary)
      Column() {
        this.runs(block, this.bodySize, false)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  quoteBlock(block: MdBlock) {
    Column() {
      this.runs(block, this.bodySize, false)
    }
    .alignItems(HorizontalAlign.Start)
    .border({ width: { left: AppLine.emphasis }, color: AppColor.border_strong })
    .padding({ left: AppSpace.sm })
  }

  build() {
    Column({ space: AppSpace.xs }) {
      ForEach(this.model(), (block: MdBlock) => {
        if (block.kind === MdKind.code) {
          this.codeBlock(block)
        } else if (block.kind === MdKind.rule) {
          Divider()
            .color(AppColor.border_strong)

        } else if (block.kind === MdKind.head) {
          Column() {
            this.runs(block, this.headSize(block), true)
          }
          .alignItems(HorizontalAlign.Start)
        } else if (block.kind === MdKind.list) {
          this.listBlock(block)
        } else if (block.kind === MdKind.quote) {
          this.quoteBlock(block)
        } else {
          Column() {
            this.runs(block, this.bodySize, false)
          }
          .alignItems(HorizontalAlign.Start)
        }
      }, (block: MdBlock, index: number) => this.sig(block, index))
    }
    .alignItems(HorizontalAlign.Start)
  }
}
