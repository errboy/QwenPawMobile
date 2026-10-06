/**
 * This chat's files and media, in one list.
 *
 * The transcript is the source: the server owns it and the phone already holds it,
 * so the list needs no endpoint of its own and cannot drift from what the bubbles
 * show. A row is therefore only ever a view over a message that is on screen.
 *
 * A component with @Prop rows, not a @Builder: the list changes while a run streams
 * in, and a builder called by value would keep showing the frame it was built on.
 */
import { AppColor, AppLine, AppRadius, AppSpace, AppType, AppMeasure } from '../../theme/Theme';
import { AssetRow } from '../../model/Asset';
import { QuoteKind } from '../../model/Attachment';
import { Copy } from '../../l10n/Copy';
import { humanBytes } from '../../core/Format';

@Component
export struct AssetPanel {
  @Prop rows: AssetRow[];
  @Prop bp: string;
  /** One line under the list: what is happening now, or what the last action did. */
  @Prop status: string;
  onClose: () => void = (): void => {};
  onOpen: (row: AssetRow) => void = (): void => {};
  onLocate: (row: AssetRow) => void = (): void => {};
  onSave: (row: AssetRow) => void = (): void => {};
  onForward: (row: AssetRow) => void = (): void => {};
  // Not 'onDrop': that name belongs to the drop event on CustomComponent.
  onDropCopy: (row: AssetRow) => void = (): void => {};
  /** Key of the row whose local copy is about to be deleted; '' hides the confirm. */
  @State confirmKey: string = '';

  private kindLabel(row: AssetRow): string {
    if (row.kind === QuoteKind.IMAGE) {
      return Copy.assets_kind_image;
    }
    if (row.kind === QuoteKind.VIDEO) {
      return Copy.assets_kind_video;
    }
    if (row.kind === QuoteKind.AUDIO) {
      return Copy.assets_kind_audio;
    }
    return Copy.assets_kind_file;
  }

  /** First line's right side: when it arrived, then where its bytes are right now. */
  private metaLine(row: AssetRow): string {
    const where = row.cached
      ? Copy.fill(Copy.assets_local, humanBytes(row.size)) : Copy.assets_remote;
    return row.stamp.length > 0 ? Copy.fill2(Copy.chat_file_meta, row.stamp, where) : where;
  }

  private pending(): AssetRow | undefined {
    for (const row of this.rows) {
      if (row.key === this.confirmKey) {
        return row;
      }
    }
    return undefined;
  }

  private confirmName(): string {
    const row = this.pending();
    return row === undefined ? '' : row.name;
  }

  @Builder
  action(label: string, tint: Resource, on: () => void) {
    Text(label)
      .fontSize(AppType.caption)
      .fontColor(tint)
      .backgroundColor(AppColor.surface_subtle)
      .borderRadius(AppRadius.pill)
      .padding({ left: AppSpace.sm, right: AppSpace.sm, top: AppSpace.xxs, bottom: AppSpace.xxs })
      .margin({ right: AppSpace.xxs, bottom: AppSpace.xxs })
      .onClick(on)
  }

  @Builder
  rowView(row: AssetRow) {
    Column({ space: AppSpace.xxs }) {
      Row({ space: AppSpace.xs }) {
        Text(this.kindLabel(row))
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_tertiary)
        Blank()
        Text(this.metaLine(row))
          .fontSize(AppType.caption)
          .fontColor(row.cached ? AppColor.text_secondary : AppColor.text_quaternary)
      }
      .width('100%')

      // The name line is the open target, and the row ends at its right edge. The
      // chips below must therefore not be pushed to that same edge: 删除副本 used to
      // sit directly under 打开 ›, one line apart, and a tap aimed at 打开 landed on
      // the only destructive control in the panel.
      Row({ space: AppSpace.xs }) {
        Text(row.name)
          .fontSize(AppType.body)
          .fontColor(AppColor.text)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(Copy.assets_open)
          .fontSize(AppType.caption)
          .fontColor(AppColor.accent_text)
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')
      .onClick((): void => {
        this.onOpen(row);
      })

      // Wrapping, not one Row: at a large system font the four chips do not fit the
      // narrowest bucket, and a chip measured past the window edge is untappable.
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        this.action(Copy.assets_locate, AppColor.accent_text, (): void => {
          this.onLocate(row);
        })
        this.action(Copy.assets_save, AppColor.accent_text, (): void => {
          this.onSave(row);
        })
        this.action(Copy.assets_forward, AppColor.accent_text, (): void => {
          this.onForward(row);
        })
        if (row.cached) {
          this.action(Copy.assets_drop, AppColor.error_text, (): void => {
            this.confirmKey = row.key;
          })
        }
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpace.sm)
    .backgroundColor(AppColor.surface)
    .border({ width: AppLine.thin, color: AppColor.border_subtle })
    .borderRadius(AppRadius.row)
    .width('100%')
  }

  @Builder
  confirmSheet() {
    Column() {
      Column({ space: AppSpace.sm }) {
        Text(Copy.assets_drop_title)
          .fontSize(AppType.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.text)
        Text(Copy.fill(Copy.assets_drop_body, this.confirmName()))
          .fontSize(AppType.body)
          .fontColor(AppColor.text_secondary)
        Row({ space: AppSpace.sm }) {
          Blank()
          Text(Copy.cancel)
            .fontSize(AppType.body)
            .fontColor(AppColor.text_secondary)
            .padding(AppSpace.sm)
            .onClick((): void => {
              this.confirmKey = '';
            })
          Text(Copy.assets_drop)
            .fontSize(AppType.body)
            .fontColor(AppColor.error_text)
            .padding(AppSpace.sm)
            .onClick((): void => {
              const row = this.pending();
              this.confirmKey = '';
              if (row !== undefined) {
                this.onDropCopy(row);
              }
            })
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding(AppSpace.lg)
      .backgroundColor(AppColor.surface_raised)
      .borderRadius(AppRadius.card)
      .width(AppMeasure.panel(this.bp))
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.scrim)
  }

  build() {
    Stack() {
      // The close target is a layer under the card, not the Stack: a click on a row
      // bubbles to its ancestors, and a handler on the Stack would close the panel
      // on the same tap that was meant to save or forward.
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(AppColor.scrim)
        .onClick((): void => {
          this.onClose();
        })

      Column({ space: AppSpace.sm }) {
        Row({ space: AppSpace.sm }) {
          Text(Copy.assets_title)
            .fontSize(AppType.title)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColor.text)
            .layoutWeight(1)
          Text(Copy.assets_close)
            .fontSize(AppType.body)
            .fontColor(AppColor.accent_text)
            .onClick((): void => {
              this.onClose();
            })
        }
        .width('100%')

        Text(Copy.assets_note)
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_quaternary)
          .width('100%')

        if (this.rows.length === 0) {
          Text(Copy.assets_empty)
            .fontSize(AppType.body)
            .fontColor(AppColor.text_tertiary)
            .width('100%')
        } else {
          Scroll() {
            Column({ space: AppSpace.xs }) {
              ForEach(this.rows, (row: AssetRow) => {
                this.rowView(row)
              }, (row: AssetRow): string => `${row.key}_${row.cached}_${row.size}_${row.stamp}`)
            }
            .width('100%')
          }
          .scrollBar(BarState.Auto)
          // A Scroll centers its child by default, which floats two rows into the
          // middle of the card.
          .align(Alignment.Top)
          .width('100%')
          .layoutWeight(1)
        }

        if (this.status.length > 0) {
          Text(this.status)
            .fontSize(AppType.caption)
            .fontColor(AppColor.text_secondary)
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding(AppSpace.lg)
      .backgroundColor(AppColor.surface_raised)
      .borderRadius(AppRadius.card)
      .width(AppMeasure.panel(this.bp))
      .height('86%')

      if (this.confirmKey.length > 0) {
        this.confirmSheet()
      }
    }
    .alignContent(Alignment.Center)
    .width('100%')
    .height('100%')
  }
}
