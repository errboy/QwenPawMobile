/**
 * Window rows for the home list.
 *
 * The foreground chat gets its own card because it is the one the phone is
 * actually sharing with the desktop; everything else is a compact row.
 */
import { AppColor, AppLine, AppRadius, AppSize, AppSpace, AppType } from '../../theme/Theme';
import { ChatSpec } from '../../model/Dtos';
import { ChatStatus } from '../../core/Wire';
import { zoneStamp } from '../../core/Format';
import { Copy } from '../../l10n/Copy';

@Component
export struct ForegroundCard {
  @Prop chat: ChatSpec;
  onOpen: (chat: ChatSpec) => void = (): void => {};

  private running(): boolean {
    return this.chat.status === ChatStatus.RUNNING;
  }

  build() {
    Column({ space: AppSpace.xxs }) {
      Row({ space: AppSpace.xs }) {
        Text(Copy.home_foreground_badge)
          .fontSize(AppType.caption)
          .fontColor(AppColor.on_action)
          .backgroundColor(AppColor.accent_action)
          .padding({ left: AppSpace.sm, right: AppSpace.sm, top: AppSpace.xxs, bottom: AppSpace.xxs })
          .borderRadius(AppRadius.control)
        if (this.running()) {
          Text(Copy.home_running_chip)
            .fontSize(AppType.caption)
            .fontColor(AppColor.success)
        }
        Blank()
        Text(Copy.home_resume)
          .fontSize(AppType.secondary)
          .fontColor(AppColor.accent_text)
      }
      .width('100%')

      Text(this.chat.name)
        .fontSize(AppType.subtitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColor.text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(Copy.home_foreground_hint)
        .fontSize(AppType.caption)
        .fontColor(AppColor.text_tertiary)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(AppSpace.md)
    .backgroundColor(AppColor.surface)
    .borderRadius(AppRadius.card)
    .border({ width: AppLine.emphasis, color: AppColor.accent_action })
    .onClick(() => {
      this.onOpen(this.chat);
    })
  }
}

@Component
export struct SessionRow {
  @Prop chat: ChatSpec;
  onOpen: (chat: ChatSpec) => void = (): void => {};
  /** Promote this window to the main one without opening it. */
  onPin: (chat: ChatSpec) => void = (): void => {};

  private running(): boolean {
    return this.chat.status === ChatStatus.RUNNING;
  }

  private stamp(): string {
    return zoneStamp(this.chat.updated_at);
  }

  build() {
    Column({ space: AppSpace.xxs }) {
      Row({ space: AppSpace.xs }) {
        if (this.running()) {
          // A plain filled box, not Circle().fill(): that overload landed after
          // this project's compatible SDK version.
          Row()
            .width(AppSize.status_dot)
            .height(AppSize.status_dot)
            .backgroundColor(AppColor.success)
            .borderRadius(AppRadius.pill)
        }
        Text(this.chat.name)
          .fontSize(AppType.body)
          .fontColor(AppColor.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.running()) {
          Text(Copy.home_row_running)
            .fontSize(AppType.caption)
            .fontColor(AppColor.success)
        }
        // The window list sorts by this same value, so the row that reads newest
        // is the newest. Names repeat — the desktop calls a fresh window '新会话'
        // and every one of them keeps that name until it is renamed on the PC.
        if (this.stamp().length > 0) {
          Text(this.stamp())
            .fontSize(AppType.caption)
            .fontColor(AppColor.text_tertiary)
        }
      }
      .width('100%')

      Text(this.chat.channel)
        .fontSize(AppType.caption)
        .fontColor(AppColor.text_tertiary)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(AppSpace.sm)
    .backgroundColor(AppColor.surface)
    .borderRadius(AppRadius.card)
    .border({ width: AppLine.thin, color: AppColor.border_subtle })
    .onClick(() => {
      this.onOpen(this.chat);
    })
    .gesture(LongPressGesture({ duration: 500 }).onAction((): void => {
      this.onPin(this.chat);
    }))
  }
}
