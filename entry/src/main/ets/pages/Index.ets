/**
 * Sign-in page: pick a server, then log in.
 *
 * Typing an address on a phone was the reason this page changed. It now lists the
 * addresses the settings page saved plus whatever the LAN sweep found answering
 * /api/auth/status, and the login button submits the credentials saved on the
 * settings page against the selected row.
 *
 * Still thin on purpose: probing, persistence and the client configuration all
 * live in AppStore, so this file is only list state and copy.
 */
import { common } from '@kit.AbilityKit';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { AppButton } from '../ui/common/AppButton';
import { LanScan, LanTarget } from '../net/LanScan';
import { AppColor, AppLine, AppMeasure, AppRadius, AppSize, AppSpace, AppType } from '../theme/Theme';
import { Copy } from '../l10n/Copy';
import { Bp } from '../core/Breakpoint';
import { Failure, FailureKind } from '../core/Failure';
import { StoreHub } from '../state/StoreHub';

@Entry
@Component
struct Index {
  @State savedRows: LanTarget[] = [];
  @State foundRows: LanTarget[] = [];
  @State selected: string = '';
  @State scanning: boolean = false;
  @State scanDone: number = 0;
  @State scanTotal: number = 0;
  @State scanFound: number = 0;
  @State statusMsg: string = '';
  @State busy: boolean = false;
  @State hasSaved: boolean = false;
  @StorageProp(Bp.KEY) wBp: string = Bp.sm;
  /** Created once so detach can identify the same closure. */
  private pull: () => void = (): void => {};

  private hub(): StoreHub {
    return StoreHub.shared();
  }

  private ctx(): common.Context | undefined {
    return this.getUIContext().getHostContext() as common.Context | undefined;
  }

  aboutToAppear(): void {
    // Default 上抬 only keeps the focused field visible, so everything below it
    // (密码, 保存并返回) hides under the keyboard on tall windows. This is a window
    // call and survives router pushes, so setting it here covers every page.
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.pull = (): void => {
      this.sync();
    };
    this.hub().app.attachView(this.pull);
    const ctx = this.ctx();
    if (ctx === undefined) {
      return;
    }
    this.hub().start(ctx).then((): void => {
      this.sync();
      this.hub().app.probeSaved();
    });
  }

  aboutToDisappear(): void {
    this.hub().app.detachView(this.pull);
  }

  /** Coming back from the settings page: the list and the selection may have moved. */
  onPageShow(): void {
    const ctx = this.ctx();
    if (ctx === undefined) {
      this.sync();
      return;
    }
    this.hub().start(ctx).then((): void => {
      this.sync();
      this.hub().app.probeSaved();
    });
  }

  private sync(): void {
    const app = this.hub().app;
    this.savedRows = app.savedRows;
    this.foundRows = app.discovered;
    this.selected = app.selected;
    this.scanning = app.scanning;
    this.scanDone = app.scanDone;
    this.scanTotal = app.scanTotal;
    this.scanFound = app.scanFound;
    this.hasSaved = app.hasSavedSession();
  }

  private nothingPicked(): boolean {
    return this.savedRows.length === 0 && this.foundRows.length === 0;
  }

  /** '192.168.1.23:8088' rather than the full URL: the scheme is noise on a row. */
  private labelOf(t: LanTarget): string {
    return LanScan.hostOf(t.url);
  }

  private statusOf(t: LanTarget): string {
    if (!t.online) {
      return Copy.login_status_unprobed;
    }
    return Copy.fillN(Copy.login_latency, t.latencyMs);
  }

  private async doScan(): Promise<void> {
    const app = this.hub().app;
    if (app.scanning) {
      return;
    }
    this.statusMsg = '';
    const found = await app.scanLan();
    if (LanScan.localPrefix().length === 0) {
      this.statusMsg = Copy.login_no_network;
    } else if (found === 0) {
      this.statusMsg = Copy.login_none_found;
    }
  }

  private async doLogin(): Promise<void> {
    const ctx = this.ctx();
    if (ctx === undefined) {
      return;
    }
    this.busy = true;
    this.statusMsg = Copy.connecting;
    try {
      await this.hub().app.signInWithConfig(ctx);
      this.statusMsg = '';
      await this.goHome();
    } catch (e) {
      this.statusMsg = Index.copyFor(Failure.from(e as Object));
    } finally {
      this.busy = false;
    }
  }

  private static copyFor(failure: Failure): string {
    if (failure.isUnauthorized()) {
      return Copy.bad_credentials;
    }
    if (failure.kind === FailureKind.Locked) {
      return Copy.account_locked;
    }
    // The gate writes its refusal reasons in Chinese for exactly this screen —
    // "该地址不在允许网段内" tells the user to fix the config, while
    // "HTTP 403 /auth/status" only tells them something failed.
    if (failure.detail !== '') {
      return Copy.fill(Copy.login_failed, failure.detail);
    }
    return Copy.fill(Copy.login_failed, failure.message);
  }

  private async goHome(): Promise<void> {
    const hub = this.hub();
    await hub.app.refreshAgents();
    hub.poller.start();
    hub.poller.poke();
    this.getUIContext().getRouter().pushUrl({ url: 'pages/HomePage' });
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppType.body)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppColor.text_secondary)
      .width(AppMeasure.text(this.wBp))
  }

  @Builder
  serverRow(t: LanTarget, fromSaved: boolean) {
    Row({ space: AppSpace.sm }) {
      // A plain filled box, not Circle().fill(): that overload landed after
      // this project's compatible SDK version.
      Row()
        .width(AppSize.status_dot)
        .height(AppSize.status_dot)
        .backgroundColor(t.online ? AppColor.success : AppColor.border_strong)
        .borderRadius(AppRadius.pill)
      Column({ space: AppSpace.xxs }) {
        Text(this.labelOf(t))
          .fontSize(AppType.body)
          .fontColor(AppColor.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.rowNote(t, fromSaved))
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_tertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.statusOf(t))
        .fontSize(AppType.caption)
        .fontColor(t.online ? AppColor.success : AppColor.text_quaternary)
    }
    .width(AppMeasure.text(this.wBp))
    .padding(AppSpace.sm)
    .backgroundColor(this.selected === t.url ? AppColor.accent_soft : AppColor.surface)
    .border({
      width: this.selected === t.url ? AppLine.emphasis : AppLine.thin,
      color: this.selected === t.url ? AppColor.accent_action : AppColor.border_subtle
    })
    .borderRadius(AppRadius.row)
    .onClick(() => {
      this.hub().app.pick(t.url);
    })
  }

  private rowNote(t: LanTarget, fromSaved: boolean): string {
    const origin = fromSaved ? Copy.login_saved_section : Copy.login_found_section;
    if (!t.online) {
      return `${origin} · ${Copy.login_status_offline}`;
    }
    const auth = t.authEnabled ? Copy.login_auth_required : Copy.login_auth_open;
    return `${origin} · ${auth}`;
  }

  build() {
    Scroll() {
      Column({ space: AppSpace.md }) {
        Text(Copy.app_name)
          .fontSize(AppType.display)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.text)
          .margin({ top: AppSpace.huge })
        Text(Copy.login_pick_hint)
          .fontSize(AppType.secondary)
          .fontColor(AppColor.text_secondary)
          .width(AppMeasure.text(this.wBp))

        if (this.savedRows.length > 0) {
          this.sectionTitle(Copy.login_saved_section)
          ForEach(this.savedRows, (t: LanTarget) => {
            this.serverRow(t, true)
          }, (t: LanTarget): string => Index.rowKey(t))
        }

        if (this.foundRows.length > 0) {
          this.sectionTitle(Copy.login_found_section)
          ForEach(this.foundRows, (t: LanTarget) => {
            this.serverRow(t, false)
          }, (t: LanTarget): string => Index.rowKey(t))
        }

        if (this.nothingPicked()) {
          Text(Copy.login_empty)
            .fontSize(AppType.body)
            .fontColor(AppColor.text_secondary)
            .width(AppMeasure.text(this.wBp))
        }

        if (this.scanning) {
          Text(Copy.fillNums(Copy.login_scan_progress, [this.scanDone, this.scanTotal, this.scanFound]))
            .fontSize(AppType.caption)
            .fontColor(AppColor.text_secondary)
            .width(AppMeasure.text(this.wBp))
        }

        if (this.selected.length > 0) {
          Text(Copy.fill(Copy.login_selected, this.selected))
            .fontSize(AppType.caption)
            .fontColor(AppColor.accent_text)
            .width(AppMeasure.text(this.wBp))
        }

        AppButton({
          label: this.busy ? Copy.action_login_busy : Copy.action_login,
          grow: true,
          disabled: this.busy || this.selected.length === 0,
          onTap: (): void => {
            this.doLogin();
          }
        })
        .width(AppMeasure.text(this.wBp))

        Row({ space: AppSpace.sm }) {
          AppButton({
            label: this.scanning ? Copy.action_scanning : Copy.action_scan,
            quiet: true,
            disabled: this.scanning,
            onTap: (): void => {
              this.doScan();
            }
          })
            .layoutWeight(1)
          AppButton({
            label: Copy.action_open_config,
            quiet: true,
            onTap: (): void => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/SettingsPage' });
            }
          })
            .layoutWeight(1)
        }
        .width(AppMeasure.text(this.wBp))

        if (this.hasSaved && this.hub().app.server === this.selected) {
          AppButton({
            label: Copy.action_use_saved,
            quiet: true,
            grow: true,
            onTap: (): void => {
              this.goHome();
            }
          })
            .width(AppMeasure.text(this.wBp))
        }

        if (this.statusMsg.length > 0) {
          Text(this.statusMsg)
            .fontSize(AppType.secondary)
            .fontColor(AppColor.error_text)
            .width(AppMeasure.text(this.wBp))
        }
      }
      .padding({ left: AppSpace.xl, right: AppSpace.xl, bottom: AppSpace.xxl })
      .width('100%')
    }
    .height('100%')
    .backgroundColor(AppColor.bg)
  }

  /** Latency is part of the key so a re-probe repaints the row. */
  private static rowKey(t: LanTarget): string {
    return `${t.url}|${t.online ? 1 : 0}|${t.latencyMs}`;
  }
}
