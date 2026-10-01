/**
 * Login configuration.
 *
 * Everything the sign-in step needs except the choice of server lives here: the
 * list of known addresses, the port a LAN sweep uses, and the credentials the
 * login button will submit. The login page itself is only a picker.
 *
 * Like the other pages this file holds no domain logic: AppStore owns the
 * persisted shape, and saving is one call.
 */
import { common } from '@kit.AbilityKit';
import { AppButton } from '../ui/common/AppButton';
import { ApiClient } from '../net/ApiClient';
import { LanScan } from '../net/LanScan';
import { AppColor, AppLine, AppRadius, AppSize, AppSpace, AppType } from '../theme/Theme';
import { Copy } from '../l10n/Copy';
import { StoreHub } from '../state/StoreHub';

@Entry
@Component
struct SettingsPage {
  @State urls: string[] = [];
  @State newUrl: string = '';
  @State portText: string = '';
  @State user: string = '';
  @State pass: string = '';
  @State localIp: string = '';
  @State statusMsg: string = '';
  @State busy: boolean = false;

  private hub(): StoreHub {
    return StoreHub.shared();
  }

  private ctx(): common.Context | undefined {
    return this.getUIContext().getHostContext() as common.Context | undefined;
  }

  aboutToAppear(): void {
    const ctx = this.ctx();
    if (ctx === undefined) {
      return;
    }
    this.hub().start(ctx).then((): void => {
      this.sync();
    });
  }

  private sync(): void {
    const app = this.hub().app;
    this.urls = app.servers.slice();
    this.portText = `${app.port}`;
    this.user = app.configUsername;
    this.pass = app.password;
    this.localIp = LanScan.localAddress();
  }

  private addServer(): void {
    const url = ApiClient.normalize(this.newUrl);
    if (url.length === 0) {
      this.statusMsg = Copy.config_invalid;
      return;
    }
    if (this.urls.indexOf(url) >= 0) {
      this.statusMsg = Copy.config_duplicate;
      return;
    }
    this.urls = this.urls.concat([url]);
    this.newUrl = '';
    this.statusMsg = '';
  }

  private removeServer(url: string): void {
    this.urls = this.urls.filter((u: string): boolean => u !== url);
  }

  /** The port the form currently holds, with the same fallback save() applies. */
  private portValue(): number {
    const parsed = parseInt(this.portText, 10);
    return parsed >= 1 && parsed <= 65535 ? parsed : LanScan.DEFAULT_PORT;
  }

  private save(): void {
    const ctx = this.ctx();
    if (ctx === undefined) {
      return;
    }
    this.busy = true;
    this.hub().app.saveConfig(ctx, this.urls, this.portValue(), this.user, this.pass)
      .then((): void => {
        this.busy = false;
        this.getUIContext().getRouter().back();
      })
      .catch((e: Object): void => {
        this.busy = false;
        this.statusMsg = `${e}`;
      });
  }

  @Builder
  field(label: string, placeholder: string, value: string, secret: boolean,
    onValue: (v: string) => void) {
    Column({ space: AppSpace.xxs }) {
      Text(label)
        .fontSize(AppType.body)
        .fontColor(AppColor.text)
      TextInput({ text: value, placeholder: placeholder })
        .type(secret ? InputType.Password : InputType.Normal)
        .fontSize(AppType.body)
        .fontColor(AppColor.text)
        .backgroundColor(AppColor.surface)
        .border({ width: AppLine.thin, color: AppColor.border })
        .borderRadius(AppRadius.control)
        .height(AppSize.input_min)
        .onChange((v: string) => {
          onValue(v);
        })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  sectionTitle(title: string, note: string) {
    Column({ space: AppSpace.xxs }) {
      Text(title)
        .fontSize(AppType.subtitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColor.text)
      Text(note)
        .fontSize(AppType.caption)
        .fontColor(AppColor.text_tertiary)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  serverRow(url: string) {
    Row({ space: AppSpace.sm }) {
      Text(url)
        .fontSize(AppType.body)
        .fontColor(AppColor.text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      AppButton({
        label: Copy.config_delete,
        quiet: true,
        onTap: (): void => {
          this.removeServer(url);
        }
      })
    }
    .width('100%')
    .padding({ left: AppSpace.sm, right: AppSpace.xs, top: AppSpace.xs, bottom: AppSpace.xs })
    .backgroundColor(AppColor.surface)
    .border({ width: AppLine.thin, color: AppColor.border_subtle })
    .borderRadius(AppRadius.row)
  }

  build() {
    Scroll() {
      Column({ space: AppSpace.md }) {
        Row({ space: AppSpace.sm }) {
          AppButton({
            label: Copy.config_back,
            quiet: true,
            onTap: (): void => {
              this.getUIContext().getRouter().back();
            }
          })
          Text(Copy.config_title)
            .fontSize(AppType.title)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColor.text)
        }
        .width('100%')
        .margin({ top: AppSpace.lg })

        this.sectionTitle(Copy.config_servers_label, Copy.config_server_hint)
        if (this.urls.length === 0) {
          Text(Copy.config_empty_list)
            .fontSize(AppType.secondary)
            .fontColor(AppColor.warning_text)
            .width('100%')
        }
        ForEach(this.urls, (url: string) => {
          this.serverRow(url)
        }, (url: string): string => url)

        Row({ space: AppSpace.sm }) {
          TextInput({ text: this.newUrl, placeholder: Copy.config_new_placeholder })
            .fontSize(AppType.body)
            .fontColor(AppColor.text)
            .backgroundColor(AppColor.surface)
            .border({ width: AppLine.thin, color: AppColor.border })
            .borderRadius(AppRadius.control)
            .height(AppSize.input_min)
            .layoutWeight(1)
            .onChange((v: string): void => {
              this.newUrl = v;
            })
          AppButton({
            label: Copy.config_add,
            onTap: (): void => {
              this.addServer();
            }
          })
        }
        .width('100%')

        Column({ space: AppSpace.xxs }) {
          Text(Copy.config_port_label)
            .fontSize(AppType.body)
            .fontColor(AppColor.text)
          Row({ space: AppSpace.sm }) {
            TextInput({ text: this.portText, placeholder: `${LanScan.DEFAULT_PORT}` })
              .type(InputType.Number)
              .fontSize(AppType.body)
              .fontColor(AppColor.text)
              .backgroundColor(AppColor.surface)
              .border({ width: AppLine.thin, color: AppColor.border })
              .borderRadius(AppRadius.control)
              .height(AppSize.input_min)
              .width(120)
              .onChange((v: string): void => {
                this.portText = v;
              })
            Text(Copy.config_port_hint)
              .fontSize(AppType.caption)
              .fontColor(AppColor.text_tertiary)
              .layoutWeight(1)
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Column({ space: AppSpace.xxs }) {
          Text(this.localIp.length > 0 ? Copy.fill(Copy.config_local_address, this.localIp)
            : Copy.config_local_unknown)
            .fontSize(AppType.caption)
            .fontColor(AppColor.text_tertiary)
          if (this.localIp.length > 0) {
            Text(Copy.fill2(Copy.config_scan_range, LanScan.localPrefix(), LanScan.localPrefix()))
              .fontSize(AppType.caption)
              .fontColor(AppColor.text_tertiary)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        this.sectionTitle(Copy.config_credential_label, Copy.config_credential_hint)
        this.field(Copy.username_field, Copy.username_placeholder, this.user, false,
          (v: string): void => {
            this.user = v;
          })
        this.field(Copy.password_field, Copy.password_placeholder, this.pass, true,
          (v: string): void => {
            this.pass = v;
          })

        if (this.statusMsg.length > 0) {
          Text(this.statusMsg)
            .fontSize(AppType.secondary)
            .fontColor(AppColor.error_text)
            .width('100%')
        }

        Text(Copy.fillNums(Copy.config_saved_line, [this.urls.length, this.portValue()]))
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_quaternary)
          .width('100%')

        AppButton({
          label: Copy.config_save,
          grow: true,
          disabled: this.busy,
          onTap: (): void => {
            this.save();
          }
        })
      }
      .padding({ left: AppSpace.xl, right: AppSpace.xl, bottom: AppSpace.xxl })
      .width('100%')
    }
    .height('100%')
    .backgroundColor(AppColor.bg)
  }
}
