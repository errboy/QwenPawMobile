/**
 * One cached copy inside an opened category row.
 *
 * A component with @Prop, not a @Builder, for the same reason CleanupRow is one:
 * the tick has to follow the page's selection after the first frame.
 *
 * Deliberately quieter than the category above it — no card, a smaller and paler
 * tick, a smaller and fainter name — because two tiers that both wear a bordered
 * row are one tier to the eye. The page hangs this row from a rule instead.
 *
 * The name line is the tap target that opens the copy before it is deleted; the
 * size-and-time line under it stays as the handle when the name could not be
 * recovered. The cue is a string, not a flag, because the audio rows turn it into
 * the playing state — a Boolean could not say 'click again to stop'.
 *
 * The name ellipsises in the middle, so the suffix at the end survives: a row that
 * has to be short still says which container those bytes are.
 */
import { AppColor, AppSpace, AppType } from '../../theme/Theme';

/** The tick of a copy is a step below the tick of its category, in size and in ink. */
const TICK = 18;

@Component
export struct CleanupFileRow {
  @Prop name: string;
  @Prop detail: string;
  /** Right-hand cue on the name line; '' makes the line inert. */
  @Prop cue: string;
  @Prop on: boolean;
  onPick: (on: boolean) => void = (): void => {};
  onOpen: () => void = (): void => {};

  build() {
    Row({ space: AppSpace.xs }) {
      Checkbox()
        .select(this.on)
        .width(TICK)
        .height(TICK)
        .selectedColor(AppColor.accent_action)
        .unselectedColor(AppColor.border_strong)
        .onChange((value: boolean): void => {
          this.onPick(value);
        })
      Column({ space: AppSpace.xxs }) {
        Row({ space: AppSpace.xs }) {
          Text(this.name)
            .fontSize(AppType.caption)
            .fontColor(AppColor.text_secondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .ellipsisMode(EllipsisMode.CENTER)
            .layoutWeight(1)
          if (this.cue.length > 0) {
            Text(this.cue)
              .fontSize(AppType.caption)
              .fontColor(AppColor.accent_text)
          }
        }
        .width('100%')
        .onClick((): void => {
          if (this.cue.length > 0) {
            this.onOpen();
          }
        })
        Text(this.detail)
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_quaternary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({
      top: AppSpace.xxs,
      bottom: AppSpace.xxs
    })
  }
}
