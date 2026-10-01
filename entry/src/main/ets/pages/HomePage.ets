/**
 * Window list.
 *
 * The page holds no domain logic: AppStore owns the session, the agent picker and
 * the window list, GlobalPoller owns freshness, and this file only mirrors the
 * store's fields into @State so ArkUI re-renders.
 */
import { common } from '@kit.AbilityKit';
import { AppButton } from '../ui/common/AppButton';
import { ForegroundCard, SessionRow } from '../ui/home/SessionRow';
import { ChannelGroup, ChannelGroups } from '../ui/home/ChannelGroups';
import { AppColor, AppLine, AppRadius, AppSpace, AppType } from '../theme/Theme';
import { ThemeManager, ThemeMode } from '../theme/ThemeManager';
import { Copy } from '../l10n/Copy';
import { AgentSummary, ChatRef, ChatSpec } from '../model/Dtos';
import { StoreHub } from '../state/StoreHub';

@Entry
@Component
struct HomePage {
  @State server: string = '';
  @State user: string = '';
  @State chats: ChatSpec[] = [];
  @State agents: AgentSummary[] = [];
  @State agentText: string = '';
  @State offline: boolean = false;
  @State pendingCount: number = 0;
  @State bgCount: number = 0;
  @State foregroundId: string = '';
  @State foreground: ChatSpec = new ChatSpec();
  @State themeName: string = '';
  @State expanded: string[] = [];
  /** Created once so detach can identify the same closure. */
  private pull: () => void = (): void => {};
  private jumped: boolean = false;

  private hub(): StoreHub {
    return StoreHub.shared();
  }

  private ctx(): common.Context | undefined {
    return this.getUIContext().getHostContext() as common.Context | undefined;
  }

  aboutToAppear(): void {
    this.pull = (): void => {
      this.sync();
    };
    this.hub().app.attachView(this.pull);
    this.sync();
    this.hub().poller.poke();
  }

  aboutToDisappear(): void {
    this.hub().app.detachView(this.pull);
  }

  /** Coming back from a chat: the foreground pointer and statuses may have moved. */
  onPageShow(): void {
    this.sync();
    this.hub().poller.poke();
  }

  private sync(): void {
    const app = this.hub().app;
    this.server = app.server;
    this.user = app.username;
    this.chats = app.chats;
    this.agents = app.agents;
    this.agentText = app.currentAgentLabel();
    this.offline = app.offline;
    this.pendingCount = app.approvals.length;
    this.bgCount = app.backgroundRunning();
    this.foregroundId = app.foregroundId();
    const fg = app.foregroundChat();
    if (fg !== undefined) {
      this.foreground = fg;
    }
    this.themeName = ThemeMode.label(ThemeManager.current());
    this.autoJump();
  }

  /** First entry lands straight in the chat the phone was reading. */
  private autoJump(): void {
    if (this.jumped || this.chats.length === 0) {
      return;
    }
    this.jumped = true;
    const fg = this.hub().app.foregroundChat();
    if (fg !== undefined) {
      this.openChat(fg);
    }
  }

  private chatsOf(group: ChannelGroup): ChatSpec[] {
    return ChannelGroups.chatsIn(this.chats, group, this.foregroundId);
  }

  private groupTitle(group: ChannelGroup): string {
    return Copy.fillN(Copy.fill2(Copy.home_group_count, group.icon, group.label),
      this.chatsOf(group).length);
  }

  private runningIn(group: ChannelGroup): number {
    return ChannelGroups.runningIn(this.chats, group, this.foregroundId);
  }

  private isExpanded(key: string): boolean {
    return this.expanded.indexOf(key) >= 0;
  }

  private toggleGroup(key: string): void {
    this.expanded = this.isExpanded(key)
      ? this.expanded.filter((k: string): boolean => k !== key)
      : this.expanded.concat([key]);
  }

  private agentOptions(): SelectOption[] {
    const out: SelectOption[] = [];
    for (const a of this.agents) {
      const option: SelectOption = { value: this.hub().app.agentLabel(a) };
      out.push(option);
    }
    return out;
  }

  private agentIndex(): number {
    const id = this.hub().app.agentId;
    for (let i = 0; i < this.agents.length; i++) {
      if (this.agents[i].id === id) {
        return i;
      }
    }
    return 0;
  }

  private pickAgent(index: number): void {
    const ctx = this.ctx();
    if (ctx === undefined || index >= this.agents.length) {
      return;
    }
    const app = this.hub().app;
    const picked = this.agents[index];
    if (picked.id === app.agentId) {
      return;
    }
    app.setAgent(picked.id);
    app.saveAgent(ctx);
    this.hub().poller.poke();
  }

  /** Jump to the window owning the oldest pending approval, when listed here. */
  private jumpToApproval(): void {
    const id = this.hub().app.approvalChatId();
    if (id.length === 0) {
      return;
    }
    for (const c of this.chats) {
      if (c.id === id) {
        this.openChat(c);
        return;
      }
    }
  }

  private openChat(chat: ChatSpec): void {
    const ref = new ChatRef();
    ref.chatId = chat.id;
    ref.sessionId = chat.session_id;
    ref.userId = chat.user_id;
    ref.title = chat.name;
    const ctx = this.ctx();
    if (ctx !== undefined) {
      this.hub().app.openChat(ctx, ref);
    }
    this.getUIContext().getRouter().pushUrl({ url: 'pages/ChatPage', params: ref });
  }

  private cycleTheme(): void {
    const ctx = this.ctx();
    if (ctx === undefined) {
      return;
    }
    ThemeManager.choose(ctx, ThemeMode.next(ThemeManager.current()))
      .then((mode: string): void => {
        this.themeName = ThemeMode.label(mode);
      });
  }

  private logout(): void {
    const ctx = this.ctx();
    const hub = this.hub();
    hub.app.detachView(this.pull);
    hub.reset();
    const back = (): void => {
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' });
    };
    if (ctx === undefined) {
      back();
      return;
    }
    hub.app.signOut(ctx).then((): void => {
      back();
    });
  }

  @Builder
  header() {
    Column({ space: AppSpace.xs }) {
      Row({ space: AppSpace.sm }) {
        Text(Copy.home_title)
          .fontSize(AppType.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.text)
        Blank()
        AppButton({
          label: Copy.fill(Copy.home_theme, this.themeName),
          quiet: true,
          onTap: (): void => {
            this.cycleTheme();
          }
        })
        AppButton({
          label: Copy.home_logout,
          quiet: true,
          onTap: (): void => {
            this.logout();
          }
        })
      }
      .width('100%')

      Text(Copy.fill(Copy.home_server_line, this.server)
        + '    '
        + Copy.fill(Copy.home_user_line,
          this.user.length > 0 ? this.user : Copy.home_no_auth_user))
        .fontSize(AppType.caption)
        .fontColor(AppColor.text_tertiary)
        .width('100%')

      Row({ space: AppSpace.sm }) {
        Text(Copy.home_agent_label)
          .fontSize(AppType.body)
          .fontColor(AppColor.text_secondary)
        if (this.agents.length > 0) {
          Select(this.agentOptions())
            .value(this.agentText)
            .font({ size: AppType.body })
            .fontColor(AppColor.accent_text)
            .selected(this.agentIndex())
            .onSelect((index: number): void => {
              this.pickAgent(index);
            })
        } else {
          Text(this.agentText)
            .fontSize(AppType.body)
            .fontColor(AppColor.accent_text)
        }
        Blank()
        if (this.pendingCount > 0) {
          Text(Copy.fillN(Copy.home_approvals, this.pendingCount))
            .fontSize(AppType.caption)
            .fontColor(AppColor.error_text)
            .onClick(() => {
              this.jumpToApproval();
            })
        }
        if (this.bgCount > 0) {
          Text(Copy.fillN(Copy.home_bg_running, this.bgCount))
            .fontSize(AppType.caption)
            .fontColor(AppColor.success)
        }
      }
      .width('100%')

      if (this.offline) {
        Text(Copy.home_offline)
          .fontSize(AppType.caption)
          .fontColor(AppColor.warning_text)
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: AppSpace.lg })
  }

  @Builder
  groupHeader(group: ChannelGroup) {
    Row({ space: AppSpace.xs }) {
      Text(this.groupTitle(group))
        .fontSize(AppType.body)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColor.text_secondary)
      if (this.runningIn(group) > 0) {
        Text(Copy.fillN(Copy.home_group_running, this.runningIn(group)))
          .fontSize(AppType.caption)
          .fontColor(AppColor.success)
      }
      Blank()
      Text(this.isExpanded(group.key) ? Copy.home_group_collapse : Copy.home_group_expand)
        .fontSize(AppType.caption)
        .fontColor(AppColor.text_tertiary)
    }
    .width('100%')
    .padding(AppSpace.sm)
    .backgroundColor(AppColor.surface_subtle)
    .border({ width: AppLine.thin, color: AppColor.border_subtle })
    .borderRadius(AppRadius.row)
    .onClick(() => {
      this.toggleGroup(group.key);
    })
  }

  build() {
    Column({ space: AppSpace.sm }) {
      this.header()

      if (this.chats.length === 0) {
        Text(Copy.home_empty)
          .fontSize(AppType.body)
          .fontColor(AppColor.text_secondary)
          .width('100%')
      } else {
        // List.space takes number|string only, so the gap comes from item margins.
        List() {
          if (this.foregroundId.length > 0) {
            ListItem() {
              ForegroundCard({
                chat: this.foreground,
                onOpen: (chat: ChatSpec): void => {
                  this.openChat(chat);
                }
              })
            }
            .margin({ bottom: AppSpace.sm })
          }
          ForEach(ChannelGroups.all(), (group: ChannelGroup) => {
            if (this.chatsOf(group).length > 0) {
              ListItem() {
                this.groupHeader(group)
              }
              .margin({ bottom: AppSpace.xs })
              if (this.isExpanded(group.key)) {
                ForEach(this.chatsOf(group), (chat: ChatSpec) => {
                  ListItem() {
                    SessionRow({
                      chat: chat,
                      onOpen: (target: ChatSpec): void => {
                        this.openChat(target);
                      }
                    })
                  }
                  .margin({ bottom: AppSpace.xs })
                }, (chat: ChatSpec): string => `${chat.id}_${chat.status}`)
              }
            }
          }, (group: ChannelGroup): string => group.key)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }

      AppButton({
        label: Copy.home_refresh,
        quiet: true,
        grow: true,
        onTap: (): void => {
          this.hub().app.refreshAgents();
          this.hub().poller.poke();
        }
      })
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: AppSpace.lg, right: AppSpace.lg, bottom: AppSpace.lg })
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bg)
  }
}
