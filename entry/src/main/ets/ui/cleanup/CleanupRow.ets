/**
 * One category row on the cleanup page.
 *
 * This is a component rather than a @Builder because the tally arrives after the
 * first frame: a builder called with plain values renders once with whatever the
 * page held at that moment and never re-reads them, so every category would stay
 * frozen at 'nothing to clean'. Only a component's @Prop follows the parent.
 */
import { AppColor, AppLine, AppRadius, AppSpace, AppType } from '../../theme/Theme';
import { Copy } from '../../l10n/Copy';

@Component
export struct CleanupRow {
  @Prop label: string;
  @Prop detail: string;
  /** False means this kind of data is not on the device right now. */
  @Prop available: boolean;
  /** Ticked whole. The page derives it from its copies, so 'all of mine'. */
  @Prop on: boolean;
  /** Rows with copies worth naming one at a time get the tail that lists them. */
  @Prop expandable: boolean;
  @Prop open: boolean;
  onPick: (on: boolean) => void = (): void => {};
  onToggle: () => void = (): void => {};

  build() {
    Row({ space: AppSpace.sm }) {
      Checkbox()
        .select(this.on)
        .enabled(this.available)
        .width(24)
        .height(24)
        .selectedColor(AppColor.accent)
        .onChange((value: boolean): void => {
          this.onPick(value);
        })
      Column({ space: AppSpace.xxs }) {
        Text(this.label)
          .fontSize(AppType.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.available ? AppColor.text : AppColor.text_quaternary)
        Text(this.available ? this.detail : Copy.cleanup_nothing)
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_quaternary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.expandable) {
        Text(this.open ? Copy.cleanup_items_close : Copy.cleanup_items)
          .fontSize(AppType.caption)
          .fontColor(AppColor.accent_text)
          .padding({
            left: AppSpace.sm,
            right: AppSpace.sm,
            top: AppSpace.xs,
            bottom: AppSpace.xs
          })
          .onClick((): void => {
            this.onToggle();
          })
      }
    }
    .width('100%')
    .padding(AppSpace.sm)
    .backgroundColor(AppColor.surface)
    .border({ width: AppLine.thin, color: AppColor.border_subtle })
    .borderRadius(AppRadius.row)
  }
}
