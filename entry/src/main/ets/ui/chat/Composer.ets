/**
 * Input row, attachment tray and the send/stop controls.
 *
 * Mobile-optimized design:
 *   - Progressive expansion: 1→6 lines, then scroll
 *   - Prominent send button: circular, right-aligned, clear touch target
 *   - Compact stop button: only shown when busy, doesn't crowd the send button
 *   - Better spacing: more breathing room between elements
 *   - Long text indicator: subtle hint when approaching max lines
 *   - Two input modes: the A/T glyph in the strip above the field swaps the text field
 *     for a hold-to-talk bar. Press and hold to record, release to send it, slide up to
 *     throw it away. Text dictation is the IME's job, so the voice mode only covers
 *     sending audio.
 *   - Tools above, bar below: the mode glyph, ＋ and clearing the field are small
 *     targets on a strip of their own, so the bar is a field and a send button and the
 *     field gets the whole width.
 */
import { AppButton } from '../common/AppButton';
import { AppColor, AppLine, AppRadius, AppSize, AppSpace, AppType, AppWidth } from '../../theme/Theme';
import { Attachment, AttachSource } from '../../model/Attachment';
import { Choice, SelectorSpec } from '../../model/Choices';
import { SkillSpec, SlashCommand } from '../../model/Dtos';
import { Copy } from '../../l10n/Copy';

/**
 * How far the finger has to rise off the talk bar before releasing throws the take
 * away. Below this a slide is a wobble, not a cancel — and a wobble that cancelled
 * would silently eat a sentence someone just spoke.
 */
const CANCEL_RISE: number = 60;

/** One category block of the `/` sheet: its header plus the commands under it. */
class SlashGroup {
  category: string = '';
  rows: SlashCommand[] = [];
  /** Stays false while the sheet is a single block — one header over one group is noise. */
  headed: boolean = false;
}

@Component
export struct Composer {
  @Link text: string;
  @Link attachments: Attachment[];
  @Prop busy: boolean = false;
  @Prop uploading: boolean = false;
  @Prop suggestions: SlashCommand[] = [];
  @Prop selectors: SelectorSpec[] = [];
  /** Skills the desktop has enabled for this channel; they get one menu row that opens a picker. */
  @Prop skills: SkillSpec[] = [];
  /** A live recording turns the ＋ menu's record entry into its own stop button. */
  @Prop recording: boolean = false;
  /** Voice mode replaces the text field with the hold-to-talk bar. */
  @Prop @Watch('dropHold') voiceMode: boolean = false;
  /** The bar's own gesture state: the label has to change the moment a finger lands. */
  @State holding: boolean = false;
  @State rising: boolean = false;
  private downY: number = 0;
  onSend: () => void = (): void => {};
  onStop: () => void = (): void => {};
  onPick: (source: string) => void = (): void => {};
  onRecord: () => void = (): void => {};
  /** The talk bar under a finger: press opens the microphone, release closes it. */
  onHoldStart: () => void = (): void => {};
  /** Release: keep the take and send it, or throw it away. */
  onHoldEnd: (discard: boolean) => void = (): void => {};
  onToggleMode: () => void = (): void => {};
  onRemove: (key: string) => void = (): void => {};
  onPickCommand: (name: string) => void = (): void => {};
  /** Open the skill picker; the page writes the chosen name into the field. */
  onOpenSkills: () => void = (): void => {};
  /** Open the read-only inventory of what the desktop has mounted. */
  onOpenMcp: () => void = (): void => {};
  onPickChoice: (key: string, id: string) => void = (): void => {};
  onLongText: () => void = (): void => {};
  /** Every keystroke, so the page can keep a crash-proof draft of the text. */
  onTextChanged: () => void = (): void => {};

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
    const longText: MenuElement = {
      value: Copy.chat_long_text,
      action: (): void => {
        this.onLongText();
      }
    };
    const mcp: MenuElement = {
      value: Copy.chat_attach_mcp,
      action: (): void => {
        this.onOpenMcp();
      }
    };
    const skills: MenuElement = {
      value: Copy.chat_attach_skills,
      action: (): void => {
        this.onOpenSkills();
      }
    };
    // Skills get one row that opens a picker of their own, not a row each. A real
    // desktop has more skills than this menu has room, and a menu row cannot carry
    // the description that makes a skill identifiable — so the list lives in
    // ui/chat/SkillPanel.ets, in the same shape as the MCP inventory.
    const rows: MenuElement[] = [gallery, files, audio, record];
    if (this.skills.length === 0) {
      // Greyed rather than hidden: an empty list is a fact about the desktop, and a
      // missing row would read as the phone failing to load one. The action never
      // runs — the field is required, and this row is switched off.
      const none: MenuElement = {
        value: Copy.chat_attach_skill_none,
        enabled: false,
        action: (): void => {}
      };
      rows.push(none);
    } else {
      rows.push(skills);
    }
    rows.push(mcp);
    rows.push(longText);
    return rows;
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

  /**
   * The talk bar is a press, not a tap. Down opens the microphone, Up hands over
   * whatever was recorded, and a rise of CANCEL_RISE throws it away. A gesture the
   * system takes over counts as a rise: nothing gets sent that nobody finished
   * holding. The page decides what any of it does to the recorder.
   */
  private hold(event: TouchEvent): void {
    const y = event.touches.length > 0 ? event.touches[0].y : this.downY;
    if (event.type === TouchType.Down) {
      if (!this.holding) {
        this.holding = true;
        this.rising = false;
        this.downY = y;
        this.onHoldStart();
      }
      return;
    }
    if (event.type === TouchType.Move) {
      if (this.holding) {
        this.rising = this.downY - y > CANCEL_RISE;
      }
      return;
    }
    if (this.holding) {
      const discard = this.rising || event.type === TouchType.Cancel;
      this.holding = false;
      this.rising = false;
      this.onHoldEnd(discard);
    }
  }

  /** Leaving voice mode drops the press: a bar that is off screen holds no finger. */
  dropHold(): void {
    if (!this.voiceMode) {
      this.holding = false;
      this.rising = false;
    }
  }

  private holdLabel(): string {
    if (!this.holding) {
      return Copy.chat_voice_idle;
    }
    return this.rising ? Copy.chat_voice_cancel : Copy.chat_voice_release;
  }

  private canSend(): boolean {
    return !this.uploading && (this.text.trim().length > 0 || this.attachments.length > 0);
  }

  /**
   * The bar delivers its own take the moment the finger lifts, so in voice mode the
   * send button has nothing to do until the tray holds something the bar cannot send
   * — a picked photo, or a take started from the ＋ menu.
   */
  private showSend(): boolean {
    return !this.voiceMode || this.attachments.length > 0;
  }
  /**
   * Cuts the suggestions into one block per category. The registry's own order
   * decides which group appears first and stays intact inside each block, so the
   * sheet never reorders commands the desktop side chose to rank.
   */
  private slashGroups(rows: SlashCommand[]): SlashGroup[] {
    const out: SlashGroup[] = [];
    for (const row of rows) {
      let at = -1;
      for (let i = 0; i < out.length; i++) {
        if (out[i].category === row.category) {
          at = i;
          break;
        }
      }
      if (at < 0) {
        const fresh = new SlashGroup();
        fresh.category = row.category;
        out.push(fresh);
        at = out.length - 1;
      }
      out[at].rows.push(row);
    }
    if (out.length > 1) {
      for (const g of out) {
        g.headed = true;
      }
    }
    return out;
  }

  @Builder
  groupHeader(category: string) {
    Text(Copy.slashGroup(category))
      .fontSize(AppType.caption)
      .fontColor(AppColor.text_tertiary)
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .padding({ left: AppSpace.sm, right: AppSpace.sm, top: AppSpace.xxs })
  }

  @Builder
  trayChip(item: Attachment) {
    Row({ space: AppSpace.xs }) {
      // A quoted reference is marked because it behaves differently: no upload,
      // and the bytes are the ones the transcript already points at.
      Text(item.ref.length > 0 ? Copy.fill(Copy.chat_quoted_prefix, item.name) : item.name)
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
      // The tools strip: what the bar used to carry sideways gets its own thin line,
      // which leaves the bar itself one field and one send button and gives the field
      // the whole width. The selector chips stay on a line of their own below it —
      // sharing one row left them no room to be read.
      Row({ space: AppSpace.xs }) {
        // Measured on an emulator screenshot: the fullwidth ＋ inks 33px tall at 20fp
        // while a capital inks 40px, so the letters step down to 14fp to match it.
        Text(this.voiceMode ? Copy.chat_mode_text : Copy.chat_mode_voice)
          .fontSize(AppType.body)
          .fontColor(AppColor.accent_text)
          .textAlign(TextAlign.Center)
          .width(AppSize.icon_hit)
          .height(AppSize.icon_hit)
          .backgroundColor(AppColor.surface_raised)
          .border({ width: AppLine.thin, color: AppColor.border })
          .borderRadius(AppRadius.pill)
          .onClick(() => {
            this.onToggleMode();
          })

        Text('＋')
          .fontSize(AppType.title)
          .fontColor(AppColor.accent_text)
          .textAlign(TextAlign.Center)
          .width(AppSize.icon_hit)
          .height(AppSize.icon_hit)
          .backgroundColor(AppColor.surface_raised)
          .borderRadius(AppRadius.pill)
          .bindMenu(this.attachMenu())

        // The IME's own clear key is dead on some phones (reproduced in Huawei
        // Notepad as well), so clearing is a tool of its own. It stays on the strip
        // when the field is empty instead of arriving with the first keystroke: a key
        // that comes and goes is a key nobody finds at the moment they want it, and a
        // grey one reads as nothing-to-clear. The two states are far apart on purpose
        // — grey while there is nothing to clear, error red the moment the field has
        // text — because the red is the only glyph on this strip that throws work
        // away, and orange already belongs to the send key two steps to the right.
        // The pill keeps its background: a red plate would read as a failure banner.
        // It clears the text only — every tray chip carries its own ×.
        Text('×')
          .fontSize(AppType.title)
          .fontColor(this.text.length > 0 ? AppColor.error : AppColor.text_quaternary)
          .textAlign(TextAlign.Center)
          .width(AppSize.icon_hit)
          .height(AppSize.icon_hit)
          .backgroundColor(AppColor.surface_raised)
          .borderRadius(AppRadius.pill)
          .onClick(() => {
            if (this.text.length > 0) {
              this.text = '';
              this.onTextChanged();
            }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

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
        // A real registry is longer than a phone is tall. Without this cap and
        // Scroll the sheet grew with the list and pushed the conversation off
        // screen, so the row limit in ChatPage could not be a node bound only.
        Scroll() {
          Column() {
            ForEach(this.slashGroups(this.suggestions), (group: SlashGroup) => {
              if (group.headed) {
                this.groupHeader(group.category)
              }
              ForEach(group.rows, (item: SlashCommand) => {
                this.suggestionRow(item)
              }, (item: SlashCommand): string => item.name)
              // headed belongs in the key: narrowing `/` to `/c` leaves the one
              // surviving group with the same category, and a key that says only
              // "conversation" lets the cached header keep serving.
            }, (group: SlashGroup): string => `${group.category}:${group.headed ? 1 : 0}`)
          }
          .width('100%')
        }
        .scrollBar(BarState.Auto)
        .constraintSize({ maxHeight: AppSize.slash_max })
        .width('100%')
        .align(Alignment.Top)
        .backgroundColor(AppColor.surface_raised)
        .border({ width: AppLine.thin, color: AppColor.border })
        .borderRadius(AppRadius.control)
      }

      Row({ space: AppSpace.sm }) {
        if (this.voiceMode) {
          Button(this.holdLabel())
            .type(ButtonType.Normal)
            .fontSize(AppType.body)
            .fontColor(this.rising ? AppColor.warning : AppColor.accent_text)
            .backgroundColor(AppColor.surface)
            .border({ width: AppLine.thin, color: AppColor.border })
            .borderRadius(AppRadius.control)
            .height(AppSize.input_min)
            .layoutWeight(1)
            .onTouch((event: TouchEvent): void => {
              this.hold(event);
            })
        } else {
          TextArea({ text: this.text, placeholder: this.busy ? Copy.chat_input_busy : Copy.chat_input_placeholder })
            .fontSize(AppType.body)
            .backgroundColor(AppColor.surface)
            .border({ width: AppLine.thin, color: AppColor.border })
            .borderRadius(AppRadius.control)
            .constraintSize({ minHeight: AppSize.input_min, maxHeight: '50%' })
            .layoutWeight(1)
            .onChange((value: string) => {
              this.text = value;
              this.onTextChanged();
            })
        }

        if (this.showSend() || this.busy) {
          Column() {
            if (this.showSend()) {
              AppButton({
                label: this.busy ? Copy.chat_send : Copy.chat_send_idle,
                quiet: false,
                disabled: !this.canSend(),
                onTap: (): void => {
                  this.onSend();
                }
              })
            }

            if (this.busy) {
              AppButton({
                label: Copy.chat_stop,
                quiet: true,
                onTap: (): void => {
                  this.onStop();
                }
              })
              .margin({ top: this.showSend() ? AppSpace.xxs : 0 })
            }
          }
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: AppSpace.md, right: AppSpace.md, top: AppSpace.xs, bottom: AppSpace.xs })
  }
}
