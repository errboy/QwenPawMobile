/**
 * What the desktop has mounted, read-only.
 *
 * A message carries nothing that names an MCP client or one of its tools, and the
 * two request-context keys that touch tools only narrow what the server already
 * enabled - so there is no "run this through that" for a phone to send. What this
 * panel does answer is the question that makes a tool call look broken from
 * eleven feet away: is that client switched on at all, and which tools is it
 * exposing right now. Every switch for those answers lives in the desktop's own
 * configuration, which this app never writes.
 *
 * Only name, description, enabled and the transport *kind* are shown. url, headers,
 * command, args and env are where a key usually sits, and they are absent from the
 * shape itself (model/Dtos.ets, MCPClientInfo) so no row here can reach them by
 * accident - a phone screen gets photographed.
 *
 * @Prop rows, not a @Builder: the tool list arrives after the panel is on screen.
 */
import { AppColor, AppLine, AppRadius, AppSpace, AppType, AppMeasure } from '../../theme/Theme';
import { MCPClientInfo, MCPToolInfo } from '../../model/Dtos';
import { Copy } from '../../l10n/Copy';

@Component
export struct McpPanel {
  @Prop clients: MCPClientInfo[];
  @Prop bp: string;
  /** Key of the client whose tools are open below it; '' has none open. */
  @Prop expanded: string;
  @Prop tools: MCPToolInfo[];
  /** One line for the open client while its tools are in flight or unavailable. */
  @Prop toolsNote: string;
  onClose: () => void = (): void => {};
  onToggle: (key: string) => void = (): void => {};

  private title(row: MCPClientInfo): string {
    return row.name.length > 0 ? row.name : row.key;
  }

  @Builder
  toolRow(tool: MCPToolInfo) {
    Row({ space: AppSpace.xs }) {
      Text('·')
        .fontSize(AppType.caption)
        .fontColor(tool.enabled ? AppColor.text_secondary : AppColor.text_quaternary)
      Text(tool.name)
        .fontSize(AppType.caption)
        .fontColor(tool.enabled ? AppColor.text : AppColor.text_quaternary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (tool.description.length > 0) {
        Text(tool.description)
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_tertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '42%' })
      }
    }
    .width('100%')
  }

  @Builder
  clientRow(row: MCPClientInfo) {
    Column({ space: AppSpace.xxs }) {
      Row({ space: AppSpace.sm }) {
        Text(this.title(row))
          .fontSize(AppType.body)
          .fontColor(AppColor.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(row.enabled ? row.transport : Copy.mcp_off)
          .fontSize(AppType.caption)
          .fontColor(row.enabled ? AppColor.text_tertiary : AppColor.warning_text)
      }

      if (row.description.length > 0) {
        Text(row.description)
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_quaternary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      if (row.key === this.expanded) {
        if (this.toolsNote.length > 0) {
          Text(this.toolsNote)
            .fontSize(AppType.caption)
            .fontColor(AppColor.text_tertiary)
            .width('100%')
            .padding({ top: AppSpace.xxs })
        }
        ForEach(this.tools, (tool: MCPToolInfo) => {
          this.toolRow(tool)
        }, (tool: MCPToolInfo): string => tool.name)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: AppSpace.sm, bottom: AppSpace.sm })
    .border({ width: { bottom: AppLine.thin }, color: AppColor.border_subtle })
    .onClick((): void => {
      this.onToggle(row.key);
    })
  }

  build() {
    Stack() {
      // Under the card, not on it: a tap on a row would otherwise bubble to the
      // layer behind and close the panel on the same finger that opened a client.
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(AppColor.scrim)
        .onClick((): void => {
          this.onClose();
        })

      Column({ space: AppSpace.sm }) {
        Row({ space: AppSpace.sm }) {
          Text(Copy.mcp_title)
            .fontSize(AppType.title)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColor.text)
            .layoutWeight(1)
          Text(Copy.mcp_close)
            .fontSize(AppType.body)
            .fontColor(AppColor.accent_text)
            .onClick((): void => {
              this.onClose();
            })
        }
        .width('100%')

        Text(Copy.mcp_note)
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_quaternary)
          .width('100%')

        if (this.clients.length === 0) {
          Text(Copy.mcp_empty)
            .fontSize(AppType.body)
            .fontColor(AppColor.text_tertiary)
            .width('100%')
        } else {
          Scroll() {
            Column() {
              ForEach(this.clients, (row: MCPClientInfo) => {
                this.clientRow(row)
              }, (row: MCPClientInfo): string => row.key)
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
