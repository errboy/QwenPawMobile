/**
 * Input row, attachment tray and the send/stop controls.
 *
 * The button label carries the interrupt semantics: while a run is live, sending
 * queues this message and cancels the run, so the label says so instead of
 * pretending the message will simply go.
 */
import { AppButton } from '../common/AppButton';
import { AppColor, AppLine, AppRadius, AppSize, AppSpace, AppType, AppWidth } from '../../theme/Theme';
import { Attachment } from '../../model/Attachment';
import { Copy } from '../../l10n/Copy';

@Component
export struct Composer {
  @Link text: string;
  @Link attachments: Attachment[];
  @Prop busy: boolean = false;
  @Prop uploading: boolean = false;
  onSend: () => void = (): void => {};
  onStop: () => void = (): void => {};
  onPick: (fromGallery: boolean) => void = (): void => {};
  onRemove: (key: string) => void = (): void => {};

  private attachMenu(): MenuElement[] {
    const gallery: MenuElement = {
      value: Copy.chat_attach_gallery,
      action: (): void => {
        this.onPick(true);
      }
    };
    const files: MenuElement = {
      value: Copy.chat_attach_files,
      action: (): void => {
        this.onPick(false);
      }
    };
    return [gallery, files];
  }

  private canSend(): boolean {
    return !this.uploading && (this.text.trim().length > 0 || this.attachments.length > 0);
  }

  @Builder
  trayChip(item: Attachment) {
    Row({ space: AppSpace.xs }) {
      Text(item.name)
        .fontSize(AppType.caption)
        .fontColor(AppColor.text_secondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: AppWidth.chip_max })
      Text('×')
        .fontSize(AppType.body)
        .fontColor(AppColor.text_tertiary)
        .onClick(() => {
          this.onRemove(item.key);
        })
    }
    .padding({ left: AppSpace.sm, right: AppSpace.xs, top: AppSpace.xs, bottom: AppSpace.xs })
    .margin({ right: AppSpace.xxs, bottom: AppSpace.xxs })
    .backgroundColor(AppColor.surface_raised)
    .border({ width: AppLine.thin, color: AppColor.border })
    .borderRadius(AppRadius.pill)
  }

  build() {
    Column({ space: AppSpace.xs }) {
      if (this.attachments.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.attachments, (item: Attachment) => {
            this.trayChip(item)
          }, (item: Attachment) => item.key)
        }
        .width('100%')
      }

      Row({ space: AppSpace.sm }) {
        Button('＋')
          .type(ButtonType.Circle)
          .fontSize(AppType.title)
          .fontColor(AppColor.accent_text)
          .backgroundColor(AppColor.surface_raised)
          .height(AppSize.hit_target)
          .width(AppSize.hit_target)
          .bindMenu(this.attachMenu())

        TextArea({ text: this.text, placeholder: this.busy ? Copy.chat_input_busy : Copy.chat_input_placeholder })
          .fontSize(AppType.body)
          .backgroundColor(AppColor.surface)
          .border({ width: AppLine.thin, color: AppColor.border })
          .borderRadius(AppRadius.control)
          .constraintSize({ minHeight: AppSize.input_min, maxHeight: AppSize.input_max })
          .layoutWeight(1)
          .maxLines(4)
          .onChange((value: string) => {
            this.text = value;
          })

        AppButton({
          label: this.busy ? Copy.chat_send : Copy.chat_send_idle,
          quiet: false,
          disabled: !this.canSend(),
          onTap: (): void => {
            this.onSend();
          }
        })

        if (this.busy) {
          AppButton({
            label: Copy.chat_stop,
            quiet: true,
            onTap: (): void => {
              this.onStop();
            }
          })
        }
      }
      .width('100%')

      if (this.busy) {
        Text(Copy.chat_input_busy)
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_tertiary)
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: AppSpace.md, right: AppSpace.md, top: AppSpace.xs, bottom: AppSpace.xs })
  }
}
