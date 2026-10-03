/**
 * Full-screen text editor for long messages.
 *
 * Opens when input exceeds threshold (200 chars or 6 lines).
 * Provides a distraction-free editing experience with send/cancel actions.
 */
import { AppButton } from '../common/AppButton';
import { AppColor, AppLine, AppMeasure, AppRadius, AppSize, AppSpace, AppType } from '../../theme/Theme';
import { Copy } from '../../l10n/Copy';
import { Bp } from '../../core/Breakpoint';

@Component
export struct FullScreenEditor {
  @Link text: string;
  @Prop placeholder: string = '';
  @StorageProp(Bp.KEY) wBp: string = Bp.sm;
  onSend: () => void = (): void => {};
  onCancel: () => void = (): void => {};
  /** Every keystroke, so the page can keep a crash-proof draft of the text. */
  onTextChanged: () => void = (): void => {};

  build() {
    Column() {
      // Header bar
      Row() {
        AppButton({
          label: Copy.cancel,
          quiet: true,
          onTap: (): void => {
            this.onCancel();
          }
        })

        Text(Copy.editor_title)
          .fontSize(AppType.subtitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.text)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        AppButton({
          label: Copy.send,
          quiet: false,
          disabled: this.text.trim().length === 0,
          onTap: (): void => {
            this.onSend();
          }
        })
      }
      .width(AppMeasure.text(this.wBp))
      .padding({ left: AppSpace.md, right: AppSpace.md, top: AppSpace.sm, bottom: AppSpace.sm })
      .backgroundColor(AppColor.surface_raised)
      .border({ width: { bottom: AppLine.thin }, color: AppColor.border })

      // Text editing area
      TextArea({ text: this.text, placeholder: this.placeholder })
        .fontSize(AppType.body)
        .backgroundColor(AppColor.surface)
        .width(AppMeasure.text(this.wBp))
        .layoutWeight(1)
        .padding(AppSpace.md)
        .onChange((value: string) => {
          this.text = value;
          this.onTextChanged();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.surface)
  }
}
