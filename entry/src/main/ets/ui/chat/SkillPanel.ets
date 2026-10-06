/**
 * The skills the desktop exposes, as a picker.
 *
 * A skill runs by its name reaching the message text — the server resolves an
 * unmatched `/name` through its slash-command fallback (runtime/
 * slash_command_registry.py:48-54), which is what `/skills` itself tells a user
 * to type. So this panel is a shortcut for a token in the field, not a switch:
 * enabling a skill, and the skill's own instructions, live in the desktop's
 * workspace manifest, which this app never writes.
 *
 * It replaces one menu row per skill. A real machine has more skills than a
 * ＋ menu has room, and a list that long stopped being a menu and became a wall.
 */
import { AppColor, AppLine, AppRadius, AppSpace, AppType, AppMeasure } from '../../theme/Theme';
import { SkillSpec } from '../../model/Dtos';
import { Copy } from '../../l10n/Copy';

@Component
export struct SkillPanel {
  @Prop skills: SkillSpec[];
  @Prop bp: string;
  onClose: () => void = (): void => {};
  /** The page owns the text field, so it writes the token; this panel only names it. */
  onPick: (name: string) => void = (): void => {};

  @Builder
  skillRow(row: SkillSpec) {
    Column({ space: AppSpace.xxs }) {
      Row({ space: AppSpace.sm }) {
        Text(row.emoji.length > 0 ? `${row.emoji} ${row.name}` : row.name)
          .fontSize(AppType.body)
          .fontColor(AppColor.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        // The token the tap puts in the field, shown before the tap: what the
        // desktop dispatches on is `/name`, and the row should not imply a
        // prettier label becomes the wire form.
        Text(`/${row.name}`)
          .fontSize(AppType.caption)
          .fontColor(AppColor.accent_text)
      }
      .width('100%')

      if (row.description.length > 0) {
        Text(row.description)
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_quaternary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: AppSpace.sm, bottom: AppSpace.sm })
    .border({ width: { bottom: AppLine.thin }, color: AppColor.border_subtle })
    .onClick((): void => {
      this.onPick(row.name);
    })
  }

  build() {
    Stack() {
      // Under the card, not on it: a tap on a row would otherwise bubble to the
      // layer behind and close the panel on the same finger that picked a skill.
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(AppColor.scrim)
        .onClick((): void => {
          this.onClose();
        })

      Column({ space: AppSpace.sm }) {
        Row({ space: AppSpace.sm }) {
          Text(Copy.skills_title)
            .fontSize(AppType.title)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColor.text)
            .layoutWeight(1)
          Text(Copy.skills_close)
            .fontSize(AppType.body)
            .fontColor(AppColor.accent_text)
            .onClick((): void => {
              this.onClose();
            })
        }
        .width('100%')

        Text(Copy.skills_note)
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_quaternary)
          .width('100%')

        if (this.skills.length === 0) {
          Text(Copy.skills_empty)
            .fontSize(AppType.body)
            .fontColor(AppColor.text_tertiary)
            .width('100%')
        } else {
          Scroll() {
            Column() {
              ForEach(this.skills, (row: SkillSpec) => {
                this.skillRow(row)
              }, (row: SkillSpec): string => row.name)
            }
            .width('100%')
          }
          .scrollBar(BarState.Auto)
          .align(Alignment.Top)
          .width('100%')
          .layoutWeight(1)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding(AppSpace.lg)
      .backgroundColor(AppColor.surface_raised)
      .borderRadius(AppRadius.card)
      .width(AppMeasure.panel(this.bp))
      .height('86%')
    }
    .alignContent(Alignment.Center)
    .width('100%')
    .height('100%')
  }
}
