/**
 * Input row, attachment tray and the send/stop controls.
 *
 * The button label carries the interrupt semantics: while a run is live, sending
 * queues this message and cancels the run, so the label says so instead of
 * pretending the message will simply go.
 */
import { AppButton } from '../common/AppButton';
import { AppColor, AppLine, AppRadius, AppSize, AppSpace, AppType, AppWidth } from '../../theme/Theme';
import { Attachment, AttachSource } from '../../model/Attachment';
import { Choice, SelectorSpec } from '../../model/Choices';
import { SlashCommand } from '../../model/Dtos';
import { Copy } from '../../l10n/Copy';

@Component
export struct Composer {
  @Link text: string;
  @Link attachments: Attachment[];
  @Prop busy: boolean = false;
  @Prop uploading: boolean = false;
  @Prop suggestions: SlashCommand[] = [];
  @Prop selectors: SelectorSpec[] = [];
  /** A live recording turns the ＋ menu's record entry into its own stop button. */
  @Prop recording: boolean = false;
  onSend: () => void = (): void => {};
  onStop: () => void = (): void => {};
  onPick: (source: string) => void = (): void => {};
  onRecord: () => void = (): void => {};
  onRemove: (key: string) => void = (): void => {};
  onPickCommand: (name: string) => void = (): void => {};
  onPickChoice: (key: string, id: string) => void = (): void => {};

  private choiceMenu(spec: SelectorSpec): MenuElement[] {
    const out: MenuElement[] = [];
    for (const c of spec.choices) {
      const choice: Choice = c;
      const key = spec.key;
      const id = choice.id;
      const label = choice.hint.length > 0 ? `${choice.label} · ${choice.hint}` : choice.label;
      const item: MenuElement = {
        value: choice.selected ? `✓ ${label}` : label,
        action: (): void => {
          this.onPickChoice(key, id);
        }
      };
      out.push(item);
    }
    return out;
  }

  private attachMenu(): MenuElement[] {
    const gallery: MenuElement = {
      value: Copy.chat_attach_gallery,
      action: (): void => {
        this.onPick(AttachSource.GALLERY);
      }
    };
    const files: MenuElement = {
      value: Copy.chat_attach_files,
      action: (): void => {
        this.onPick(AttachSource.FILES);
      }
    };
    const audio: MenuElement = {
      value: Copy.chat_attach_audio,
      action: (): void => {
        this.onPick(AttachSource.AUDIO);
      }
    };
    const record: MenuElement = {
      value: this.recording ? Copy.chat_rec_stop : Copy.chat_attach_record,
      action: (): void => {
        this.onRecord();
      }
    };
    return [gallery, files, audio, record];
  }

  /**
   * A chip's menu is built once, together with the chip, so the menu's contents
   * are part of the chip's render identity: two chips whose menus differ have to
   * differ in key too, or the older menu keeps serving.
   */
  private chipKey(spec: SelectorSpec): string {
    const parts: string[] = [spec.key, spec.title, spec.selected];
    for (const c of spec.choices) {
      parts.push(`${c.id}:${c.label}:${c.hint}:${c.selected ? 1 : 0}`);
    }
    return parts.join('|');
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

  @Builder
  suggestionRow(item: SlashCommand) {
    Row({ space: AppSpace.sm }) {
      Text(`/${item.name}`)
        .fontSize(AppType.body)
        .fontColor(AppColor.accent_text)
        .fontWeight(FontWeight.Medium)
      if (item.description.length > 0) {
        Text(item.description)
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_tertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
    }
    .width('100%')
    .padding({ left: AppSpace.sm, right: AppSpace.sm, top: AppSpace.xs, bottom: AppSpace.xs })
    .onClick(() => {
      this.onPickCommand(item.name);
    })
  }

  build() {
    Column({ space: AppSpace.xs }) {
      if (this.selectors.length > 0) {
        Row({ space: AppSpace.xs }) {
          ForEach(this.selectors, (spec: SelectorSpec) => {
            if (spec.choices.length > 0) {
              Text(`${spec.title} ▾`)
                .fontSize(AppType.caption)
                .fontColor(AppColor.text_secondary)
                // Three chips share one row, so a long model name gets the ellipsis
                // rather than pushing the approval picker off the screen.
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .flexShrink(1)
                .padding({ left: AppSpace.sm, right: AppSpace.sm, top: AppSpace.xxs, bottom: AppSpace.xxs })
                .backgroundColor(AppColor.surface_raised)
                .border({ width: AppLine.thin, color: AppColor.border })
                .borderRadius(AppRadius.pill)
                .bindMenu(this.choiceMenu(spec))
            }
          }, (spec: SelectorSpec): string => this.chipKey(spec))
        }
        .width('100%')
      }

      if (this.attachments.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.attachments, (item: Attachment) => {
            this.trayChip(item)
          }, (item: Attachment) => item.key)
        }
        .width('100%')
      }

      if (this.suggestions.length > 0) {
        Column() {
          ForEach(this.suggestions, (item: SlashCommand) => {
            this.suggestionRow(item)
          }, (item: SlashCommand): string => item.name)
        }
        .width('100%')
        .backgroundColor(AppColor.surface_raised)
        .border({ width: AppLine.thin, color: AppColor.border })
        .borderRadius(AppRadius.control)
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
