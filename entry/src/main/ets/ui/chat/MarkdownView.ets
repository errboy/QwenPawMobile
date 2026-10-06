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
import { MdAlign, MdBlock, MdCell, MdKind, MdRow, MdRun, Markdown } from './Markdown';

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
    if (last.kind === MdKind.table) {
      // A table under construction still has cells to land the caret in; the last
      // row's last cell is where the next token will turn up.
      const rows: MdRow[] = last.rows;
      if (rows.length > 0) {
        const cells: MdCell[] = rows[rows.length - 1].cells;
        if (cells.length > 0) {
          cells[cells.length - 1].runs.push(MarkdownView.caret());
        }
      }
      return;
    }
    last.runs.push(MarkdownView.caret());
  }

  private static caret(): MdRun {
    const run = new MdRun();
    run.text = ' ▍';
    return run;
  }

  private static rowLen(row: MdRow): number {
    let n: number = 0;
    for (const cell of row.cells) {
      n += MarkdownView.cellLen(cell);
    }
    return n;
  }

  private static cellLen(cell: MdCell): number {
    let n: number = 0;
    for (const run of cell.runs) {
      n += run.text.length;
    }
    return n;
  }

  /**
   * A block's own text length is part of its key on purpose: without it a growing
   * stream keeps the same key and ForEach hands back the stale child. Table cells
   * count too, or a row that gains a word mid-stream never redraws.
   */
  private sig(block: MdBlock, index: number): string {
    let n: number = 0;
    for (let i = 0; i < block.runs.length; i++) {
      n += block.runs[i].text.length;
    }
    for (let i = 0; i < block.lines.length; i++) {
      n += block.lines[i].length;
    }
    for (let i = 0; i < block.rows.length; i++) {
      n += MarkdownView.rowLen(block.rows[i]);
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
  runs(items: MdRun[], size: Resource, forceBold: boolean) {
    Text() {
      ForEach(items, (run: MdRun) => {
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
        this.runs(block.runs, this.bodySize, false)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  quoteBlock(block: MdBlock) {
    Column() {
      this.runs(block.runs, this.bodySize, false)
    }
    .alignItems(HorizontalAlign.Start)
    .border({ width: { left: AppLine.emphasis }, color: AppColor.border_strong })
    .padding({ left: AppSpace.sm })
  }

  private static alignOf(align: string): HorizontalAlign {
    if (align === MdAlign.center) {
      return HorizontalAlign.Center;
    }
    return align === MdAlign.right ? HorizontalAlign.End : HorizontalAlign.Start;
  }

  /**
   * Equal-weight columns inside a full-width grid, at the smaller font: a bubble
   * is two thirds of a phone, and at body size a two-word cell wraps every line.
   * Cells wrap rather than scroll, so a long cell makes its column taller, never
   * cut off. The desktop draws the same table wider; that is the screen, not us.
   */
  @Builder
  tableBlock(block: MdBlock) {
    Column() {
      ForEach(block.rows, (row: MdRow, ri: number) => {
        Row() {
          ForEach(row.cells, (cell: MdCell) => {
            Column() {
              this.runs(cell.runs, AppType.secondary, row.head)
            }
            .layoutWeight(1)
            .alignItems(MarkdownView.alignOf(cell.align))
            .padding({
              left: AppSpace.xs,
              right: AppSpace.xs,
              top: AppSpace.xxs,
              bottom: AppSpace.xxs
            })
          }, (cell: MdCell, ci: number) => `${ci}:${MarkdownView.cellLen(cell)}`)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .backgroundColor(row.head ? AppColor.surface_sunken : Color.Transparent)
        .border({
          width: { bottom: ri === block.rows.length - 1 ? 0 : AppLine.thin },
          color: AppColor.border_subtle
        })
      }, (row: MdRow, ri: number) => `${ri}:${row.head ? 'h' : 'b'}:${MarkdownView.rowLen(row)}`)
    }
    .width('100%')
    .border({ width: AppLine.thin, color: AppColor.border_subtle })
    .borderRadius(AppRadius.control)
    .clip(true)
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
            this.runs(block.runs, this.headSize(block), true)
          }
          .alignItems(HorizontalAlign.Start)
        } else if (block.kind === MdKind.list) {
          this.listBlock(block)
        } else if (block.kind === MdKind.quote) {
          this.quoteBlock(block)
        } else if (block.kind === MdKind.table) {
          this.tableBlock(block)
        } else {
          Column() {
            this.runs(block.runs, this.bodySize, false)
          }
          .alignItems(HorizontalAlign.Start)
        }
      }, (block: MdBlock, index: number) => this.sig(block, index))
    }
    .alignItems(HorizontalAlign.Start)
  }
}
