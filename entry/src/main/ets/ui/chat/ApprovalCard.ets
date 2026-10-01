/**
 * A pending governance approval.
 *
 * The countdown reads `nowSec`, which the store refreshes every second while a
 * view is attached. v1 keyed the approval ForEach on request_id only and had no
 * clock at all, so the timer froze on whatever value it first rendered.
 *
 * Nothing here decides on the user's behalf: both buttons need a tap, and a
 * timeout is the server's business, not the phone's.
 */
import { AppButton } from '../common/AppButton';
import { AppColor, AppLine, AppRadius, AppSpace, AppType, AppWidth } from '../../theme/Theme';
import { ApprovalInfo } from '../../model/Dtos';
import { Severity } from '../../core/Wire';
import { Copy } from '../../l10n/Copy';

@Component
export struct ApprovalCard {
  @Prop approval: ApprovalInfo;
  @Prop nowSec: number;
  onDecide: (approval: ApprovalInfo, approved: boolean) => void = (): void => {};

  private secondsLeft(): number {
    const deadline = this.approval.created_at + this.approval.timeout_seconds;
    const left = deadline - this.nowSec;
    return left > 0 ? left : 0;
  }

  private headline(): string {
    const display = this.approval.tool_display_name;
    const name = display.length > 0 ? display : this.approval.tool_name;
    return Copy.fill(Copy.approval_headline, name);
  }

  private metaLine(): string {
    const time = Copy.fillN(Copy.approval_timeout_in, this.secondsLeft());
    return Copy.fill2(Copy.approval_meta, this.approval.tool_source, time);
  }

  private accent(): Resource {
    if (Severity.isError(this.approval.severity)) {
      return AppColor.error;
    }
    if (Severity.isWarning(this.approval.severity)) {
      return AppColor.warning;
    }
    return AppColor.info_border;
  }

  private bodyColor(): Resource {
    if (Severity.isError(this.approval.severity)) {
      return AppColor.error_bg;
    }
    if (Severity.isWarning(this.approval.severity)) {
      return AppColor.warning_bg;
    }
    return AppColor.info_bg;
  }

  private textColor(): Resource {
    if (Severity.isError(this.approval.severity)) {
      return AppColor.error_text;
    }
    if (Severity.isWarning(this.approval.severity)) {
      return AppColor.warning_text;
    }
    return AppColor.info_text;
  }

  build() {
    Column({ space: AppSpace.xs }) {
      Text(this.headline())
        .fontSize(AppType.body)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.textColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(this.metaLine())
        .fontSize(AppType.caption)
        .fontColor(this.textColor())
        .width('100%')
      if (this.approval.severity.length > 0) {
        Text(this.approval.severity)
          .fontSize(AppType.caption)
          .fontColor(this.textColor())
          .width('100%')
      }
      if (this.approval.exact_target.length > 0) {
        Text(this.approval.exact_target)
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_secondary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      if (this.approval.reasoning.length > 0) {
        Text(this.approval.reasoning)
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_secondary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      Text(Copy.approval_note)
        .fontSize(AppType.caption)
        .fontColor(AppColor.text_tertiary)
        .width('100%')
      Row({ space: AppSpace.sm }) {
        Blank()
        AppButton({
          label: Copy.approval_deny,
          quiet: true,
          onTap: (): void => {
            this.onDecide(this.approval, false);
          }
        })
        AppButton({
          label: Copy.approval_approve,
          quiet: false,
          onTap: (): void => {
            this.onDecide(this.approval, true);
          }
        })
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpace.sm)
    .backgroundColor(this.bodyColor())
    .border({ width: AppLine.emphasis, color: this.accent() })
    .borderRadius(AppRadius.card)
    .width(AppWidth.tool_max)
  }
}
