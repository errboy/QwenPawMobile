/**
 * Local cleanup, chosen by category — and inside a category, copy by copy.
 *
 * This page exists because a single 'clear' button asks the user to agree blind:
 * a cached clip, a recorded take and a composer preference are three different
 * losses. So each kind is listed with its own size, each copy of it with its own
 * name, bytes and last write — and a copy can be opened, played or read before it
 * is ticked, because 'what is this file' is the question the delete turns on —
 * and nothing is deleted until the second screen says what is about to go.
 *
 * The category tick is 'all of mine' rather than a second kind of delete: it
 * selects that category's copies, which is the same set the rows under it add up
 * to. One tick leaves one tick, and the confirmation names the number either way.
 *
 * Deliberately absent, in three directions: the chat transcript and the server's
 * files (the phone holds no copy of either, and the desktop exposes no delete
 * route); unsent drafts (text someone was writing, which a cache sweep has no
 * business touching); and the saved account, password and addresses, which are
 * login configuration and are emptied on that page.
 */
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppButton } from '../ui/common/AppButton';
import { CleanupFileRow } from '../ui/cleanup/CleanupFileRow';
import { CleanupRow } from '../ui/cleanup/CleanupRow';
import { AppColor, AppFont, AppMeasure, AppRadius, AppSpace, AppType } from '../theme/Theme';
import { Copy } from '../l10n/Copy';
import { Bp } from '../core/Breakpoint';
import { humanBytes } from '../core/Format';
import { Failure } from '../core/Failure';
import { Export } from '../media/Export';
import { CLEANUP_KINDS, CleanupFile, CleanupPicks, CleanupTally } from '../model/Cleanup';
import { StoreHub } from '../state/StoreHub';

/** How much of a text document the preview reads; the tail stays on the disk. */
const READ_CAP = 32 * 1024;

/** The rule a category's copies hang from, in vp. */
const FILE_RULE = 2;

/**
 * Suffixes the page reads out itself. Everything here is a file whose bytes are
 * the message — the desktop hands out notes, patches and logs — and every one of
 * them opens in the page instead of a reader app the phone may not have, which is
 * the difference between 'this is the file' and 'no app can open this'.
 */
const TEXT_EXT: string[] = ['txt', 'md', 'markdown', 'json', 'log', 'csv', 'yml', 'yaml',
  'xml', 'ini', 'conf', 'toml', 'js', 'ts', 'py', 'sh', 'bat', 'ps1', 'html', 'htm', 'css', 'sql'];

/** Lowercased suffix of a stored file name; '' when there is none to read. */
function extOf(name: string): string {
  const dot = name.lastIndexOf('.');
  if (dot < 0 || dot === name.length - 1) {
    return '';
  }
  return name.substring(dot + 1).toLowerCase();
}

@Entry
@Component
struct CleanupPage {
  @State t: CleanupTally = new CleanupTally();
  /** Names of the copies picked, whole categories and single files alike. */
  @State picked: string[] = [];
  @State onChoices: boolean = false;
  /** Which category rows are showing their copies. */
  @State open: string[] = [];
  /** The second screen. Nothing is deleted before it is confirmed here. */
  @State confirming: boolean = false;
  @State busy: boolean = false;
  @State notice: string = '';
  /** The copy the speaker is playing from this page; '' when nothing plays here. */
  @State playing: string = '';
  /** The clip shown over the page; an empty path closes the overlay. */
  @State watchPath: string = '';
  @State watchName: string = '';
  /** The text document shown over the page; an empty path closes that overlay. */
  @State readPath: string = '';
  @State readName: string = '';
  @State readText: string = '';
  /** True when the file is longer than the preview reads, so the tail is not shown. */
  @State readClipped: boolean = false;
  @StorageProp(Bp.KEY) wBp: string = Bp.sm;

  private hub(): StoreHub {
    return StoreHub.shared();
  }

  private ctx(): common.Context | undefined {
    return this.getUIContext().getHostContext() as common.Context | undefined;
  }

  aboutToAppear(): void {
    this.refresh();
  }

  onPageShow(): void {
    this.refresh();
  }

  private refresh(): void {
    const ctx = this.ctx();
    if (ctx === undefined) {
      return;
    }
    this.hub().tally(ctx).then((t: CleanupTally): void => {
      this.apply(t);
    }).catch((err: Object): void => {
      // A page that cannot read the device must not present itself as an empty one.
      this.notice = Copy.fill(Copy.cleanup_read_failed, Failure.from(err).message);
    });
  }

  private apply(t: CleanupTally): void {
    this.t = t;
    // A copy the system reclaimed on its own is not tickable, and a category that
    // emptied itself cannot stay ticked for the next sweep.
    const kept: string[] = [];
    for (const name of this.picked) {
      if (this.has(name)) {
        kept.push(name);
      }
    }
    this.picked = kept;
    if (t.choices === 0) {
      this.onChoices = false;
    }
  }

  private labelOf(kind: string): string {
    if (kind === 'video') {
      return Copy.cleanup_cat_video;
    }
    if (kind === 'audio') {
      return Copy.cleanup_cat_audio;
    }
    if (kind === 'doc') {
      return Copy.cleanup_cat_doc;
    }
    if (kind === 'record') {
      return Copy.cleanup_cat_record;
    }
    return Copy.cleanup_cat_other;
  }

  /** The copies of one category, as the device held them at the last read. */
  private filesOf(kind: string): CleanupFile[] {
    const out: CleanupFile[] = [];
    for (const f of this.t.files) {
      if (f.kind === kind) {
        out.push(f);
      }
    }
    return out;
  }

  private has(name: string): boolean {
    for (const f of this.t.files) {
      if (f.name === name) {
        return true;
      }
    }
    return false;
  }

  private checked(name: string): boolean {
    return this.picked.indexOf(name) >= 0;
  }

  /** A category is ticked when every copy of it is, which is what the tick means. */
  private isOn(kind: string): boolean {
    const list = this.filesOf(kind);
    if (list.length === 0) {
      return false;
    }
    for (const f of list) {
      if (!this.checked(f.name)) {
        return false;
      }
    }
    return true;
  }

  private setKind(kind: string, on: boolean): void {
    const next: string[] = [];
    for (const name of this.picked) {
      const f = this.copyNamed(name);
      if (f !== undefined && f.kind !== kind) {
        next.push(name);
      }
    }
    if (on) {
      for (const item of this.filesOf(kind)) {
        next.push(item.name);
      }
    }
    this.picked = next;
  }

  private toggleFile(name: string, on: boolean): void {
    const next: string[] = [];
    for (const held of this.picked) {
      if (held !== name) {
        next.push(held);
      }
    }
    if (on) {
      next.push(name);
    }
    this.picked = next;
  }

  private copyNamed(name: string): CleanupFile | undefined {
    for (const f of this.t.files) {
      if (f.name === name) {
        return f;
      }
    }
    return undefined;
  }

  private selectedOf(kind: string): number {
    let n: number = 0;
    for (const f of this.filesOf(kind)) {
      if (this.checked(f.name)) {
        n += 1;
      }
    }
    return n;
  }

  private isOpen(kind: string): boolean {
    return this.open.indexOf(kind) >= 0;
  }

  private toggleOpen(kind: string): void {
    const next: string[] = [];
    for (const held of this.open) {
      if (held !== kind) {
        next.push(held);
      }
    }
    if (!this.isOpen(kind)) {
      next.push(kind);
    }
    this.open = next;
  }

  private pickedCount(): number {
    return this.picks().count();
  }

  private picks(): CleanupPicks {
    const p = new CleanupPicks();
    p.choices = this.onChoices;
    for (const f of this.t.files) {
      if (this.checked(f.name)) {
        p.files.push(f);
      }
    }
    return p;
  }

  /** Names of what goes, for the confirmation line. Partial rows count their files. */
  private summary(): string {
    const names: string[] = [];
    for (const kind of CLEANUP_KINDS) {
      const chosen: number = this.selectedOf(kind);
      if (chosen === 0) {
        continue;
      }
      names.push(chosen === this.filesOf(kind).length ? this.labelOf(kind)
        : Copy.fillN2(Copy.cleanup_summary_part, this.labelOf(kind), chosen));
    }
    if (this.onChoices) {
      names.push(Copy.cleanup_cat_choices);
    }
    return names.join('、');
  }

  /** Fill in every category that has something to lose, or empty the lot. */
  private selectAll(): void {
    const total: number = this.t.files.length + (this.t.choices > 0 ? 1 : 0);
    const on: boolean = this.pickedCount() < total;
    const next: string[] = [];
    if (on) {
      for (const f of this.t.files) {
        next.push(f.name);
      }
    }
    this.picked = next;
    this.onChoices = on && this.t.choices > 0;
  }

  private run(): void {
    const ctx = this.ctx();
    const count: number = this.pickedCount();
    this.confirming = false;
    if (ctx === undefined || count === 0 || this.busy) {
      return;
    }
    this.busy = true;
    this.notice = '';
    this.hub().runCleanup(ctx, this.picks()).then((gone: number): void => {
      this.busy = false;
      // Those bytes are gone whatever the tally said a moment ago, so the ticks
      // go with them; refresh() then re-reads the device for what is left.
      this.picked = [];
      this.notice = Copy.fillN(Copy.cleanup_done, gone);
      this.refresh();
    }).catch((err: Object): void => {
      this.busy = false;
      this.notice = Copy.fill(Copy.notice_clear_failed, Failure.from(err).message);
    });
  }

  /** Last write to the minute, on the line under the name. */
  private whenText(ms: number): string {
    const d = new Date(ms);
    const two = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    return `${two(d.getMonth() + 1)}-${two(d.getDate())} ${two(d.getHours())}:${two(d.getMinutes())}`;
  }

  /**
   * What a row calls its copy: the recovered name when an open chat still holds the
   * reference it came from, otherwise the name the file actually has on the device.
   * Every copy is named, and every name carries its container suffix, so two rows
   * never read the same and neither reads as a category.
   */
  private shownName(f: CleanupFile): string {
    return f.label.length > 0 ? f.label : f.name;
  }

  /** The audio rows swap their cue while playing; every other row just offers 打开. */
  private cueOf(f: CleanupFile): string {
    return this.playing === f.name ? Copy.chat_audio_playing : Copy.assets_open;
  }

  /**
   * Look at the copy before agreeing to delete it. Video opens in this page's own
   * overlay; audio and recorded takes play through the one app-wide speaker; a
   * text document is read out in the page, where the bytes answer 'what is this'
   * even when the name is gone; anything else goes to whichever reader app the
   * system matches for its type.
   */
  private openFile(f: CleanupFile): void {
    if (f.kind === 'video') {
      this.watchName = this.shownName(f);
      this.watchPath = f.path;
      return;
    }
    if (f.kind === 'audio' || f.kind === 'record') {
      this.togglePlay(f);
      return;
    }
    if (TEXT_EXT.indexOf(extOf(f.path)) >= 0) {
      this.showText(f);
      return;
    }
    this.openBySystem(f);
  }

  /** The copy's own bytes on screen, capped at what a preview can read cheaply. */
  private showText(f: CleanupFile): void {
    let text = '';
    let clipped = false;
    try {
      const size = fs.statSync(f.path).size;
      const cap = Math.min(size, READ_CAP);
      const file = fs.openSync(f.path, fs.OpenMode.READ_ONLY);
      try {
        const buf = new ArrayBuffer(cap);
        const read = fs.readSync(file.fd, buf, { length: cap, offset: 0 });
        text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf, 0, read));
        clipped = size > cap;
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      this.notice = Copy.fill(Copy.assets_fetch_failed, this.shownName(f));
      return;
    }
    // Binary bytes wearing a text suffix are not something to spell out as mojibake.
    if (text.indexOf('\u0000') >= 0) {
      this.openBySystem(f);
      return;
    }
    this.readName = this.shownName(f);
    this.readText = text;
    this.readClipped = clipped;
    this.readPath = f.path;
  }

  private openBySystem(f: CleanupFile): void {
    const ctx = this.ctx();
    if (ctx === undefined) {
      return;
    }
    Export.open(ctx as common.UIAbilityContext, f.path, f.label)
      .then((detail: string): void => {
        if (detail.length > 0) {
          this.notice = detail;
        }
      });
  }

  private togglePlay(f: CleanupFile): void {
    if (this.playing === f.name) {
      this.hub().audio.stop();
      this.playing = '';
      return;
    }
    // The mark goes up before the request: play() settles without error for a take
    // that fails the handshake (the failure routes to onFail), so the tick cannot
    // be what confirms the sound.
    this.playing = f.name;
    this.hub().audio.play(f.name, f.path, (key: string): void => {
      if (this.playing === key) {
        this.playing = '';
      }
    }, (message: string): void => {
      this.playing = '';
      this.notice = Copy.fill(Copy.notice_audio_failed, message);
    });
  }

  private closeWatch(): void {
    this.watchPath = '';
    this.watchName = '';
  }

  private closeRead(): void {
    this.readPath = '';
    this.readName = '';
    this.readText = '';
    this.readClipped = false;
  }

  /** Leaving the page silences whatever it started playing. */
  onPageHide(): void {
    this.hub().audio.stop();
    this.playing = '';
  }

  /** Back closes the overlay first; a second back leaves the page. */
  onBackPress(): boolean {
    if (this.watchPath.length > 0) {
      this.closeWatch();
      return true;
    }
    if (this.readPath.length > 0) {
      this.closeRead();
      return true;
    }
    return false;
  }

  @Builder
  confirmSheet() {
    Column() {
      Column({ space: AppSpace.sm }) {
        Text(Copy.cleanup_confirm_title)
          .fontSize(AppType.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.text)
        Text(Copy.fill(Copy.cleanup_confirm_body, this.summary()))
          .fontSize(AppType.body)
          .fontColor(AppColor.text_secondary)
        Row({ space: AppSpace.sm }) {
          AppButton({
            label: Copy.cancel,
            quiet: true,
            onTap: (): void => {
              this.confirming = false;
            }
          })
          AppButton({
            label: Copy.cleanup_confirm_yes,
            onTap: (): void => {
              this.run();
            }
          })
        }
        .justifyContent(FlexAlign.End)
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding(AppSpace.lg)
      .backgroundColor(AppColor.surface_raised)
      .borderRadius(AppRadius.card)
      .width(AppMeasure.text(this.wBp))
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.scrim)
  }

  /**
   * The clip, full-screen over the page. The scrim layer is the close target and
   * sits under the card: a click on the card bubbles to its ancestors, and a
   * handler up there would close the sheet on the same tap that was meant to pause.
   */
  @Builder
  watchSheet() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(AppColor.scrim)
        .onClick((): void => {
          this.closeWatch();
        })

      Column({ space: AppSpace.sm }) {
        Row({ space: AppSpace.sm }) {
          Text(this.watchName)
            .fontSize(AppType.body)
            .fontColor(AppColor.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          AppButton({
            label: Copy.assets_close,
            quiet: true,
            onTap: (): void => {
              this.closeWatch();
            }
          })
        }
        .width('100%')

        Video({ src: `file://${this.watchPath}`, previewUri: '' })
          .autoPlay(true)
          .controls(true)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .layoutWeight(1)
      }
      .alignItems(HorizontalAlign.Start)
      .padding(AppSpace.lg)
      .backgroundColor(AppColor.surface_raised)
      .borderRadius(AppRadius.card)
      .width(AppMeasure.panel(this.wBp))
      .height('86%')
    }
    .alignContent(Alignment.Center)
    .width('100%')
    .height('100%')
  }

  /**
   * The document's own bytes, full-screen over the page — the same door video gets,
   * because a name recovered from memory can be wrong about what the file holds and
   * the bytes cannot. The mono face keeps indentation and tables readable even
   * though markdown is shown as source.
   */
  @Builder
  readSheet() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(AppColor.scrim)
        .onClick((): void => {
          this.closeRead();
        })

      Column({ space: AppSpace.sm }) {
        Row({ space: AppSpace.sm }) {
          Text(this.readName)
            .fontSize(AppType.body)
            .fontColor(AppColor.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          AppButton({
            label: Copy.assets_close,
            quiet: true,
            onTap: (): void => {
              this.closeRead();
            }
          })
        }
        .width('100%')

        Scroll() {
          Column({ space: AppSpace.xs }) {
            Text(this.readText)
              .fontSize(AppType.caption)
              .fontFamily(AppFont.mono)
              .fontColor(AppColor.text_secondary)
              .width('100%')
            if (this.readClipped) {
              Text(Copy.fill(Copy.cleanup_read_truncated, humanBytes(READ_CAP)))
                .fontSize(AppType.caption)
                .fontColor(AppColor.text_quaternary)
                .width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        .align(Alignment.Top)
        .layoutWeight(1)
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding(AppSpace.lg)
      .backgroundColor(AppColor.surface_raised)
      .borderRadius(AppRadius.card)
      .width(AppMeasure.panel(this.wBp))
      .height('86%')
    }
    .alignContent(Alignment.Center)
    .width('100%')
    .height('100%')
  }

  /**
   * The copies hung under their category: the block is inset behind a rule at the
   * card's left edge and its rows wear no card of their own, so the two tiers read
   * as one tier at a glance instead of as two lists of near-identical rows.
   */
  @Builder
  fileList(kind: string) {
    if (this.isOpen(kind)) {
      Column({ space: AppSpace.xxs }) {
        ForEach(this.filesOf(kind), (f: CleanupFile) => {
          CleanupFileRow({
            name: this.shownName(f),
            detail: Copy.fill2(Copy.cleanup_file_detail, humanBytes(f.bytes),
              this.whenText(f.modified)),
            cue: this.cueOf(f),
            on: this.checked(f.name),
            onPick: (on: boolean): void => {
              this.toggleFile(f.name, on);
            },
            onOpen: (): void => {
              this.openFile(f);
            }
          })
        }, (f: CleanupFile): string => f.name)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({
        left: AppSpace.xxl,
        right: AppSpace.xs,
        top: AppSpace.xxs,
        bottom: AppSpace.xxs
      })
      .border({ width: { left: FILE_RULE }, color: AppColor.border_strong })
    }
  }

  build() {
    Stack() {
      Scroll() {
        Column({ space: AppSpace.md }) {
          Row({ space: AppSpace.sm }) {
            AppButton({
              label: Copy.chat_back,
              quiet: true,
              onTap: (): void => {
                this.getUIContext().getRouter().back();
              }
            })
            Text(Copy.cleanup_title)
              .fontSize(AppType.title)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColor.text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            AppButton({
              label: Copy.cleanup_go_all,
              quiet: true,
              onTap: (): void => {
                this.selectAll();
              }
            })
          }
          .width(AppMeasure.panel(this.wBp))
          .margin({ top: AppSpace.lg })

          Text(Copy.cleanup_note)
            .fontSize(AppType.caption)
            .fontColor(AppColor.text_quaternary)
            .width(AppMeasure.panel(this.wBp))

          CleanupRow({
            label: Copy.cleanup_cat_video,
            detail: Copy.fill2(Copy.cleanup_media_detail, `${this.t.videoFiles}`,
              humanBytes(this.t.videoBytes)),
            available: this.t.videoFiles > 0,
            on: this.isOn('video'),
            expandable: this.t.videoFiles > 0,
            open: this.isOpen('video'),
            onPick: (on: boolean): void => {
              this.setKind('video', on);
            },
            onToggle: (): void => {
              this.toggleOpen('video');
            }
          })
          this.fileList('video')
          CleanupRow({
            label: Copy.cleanup_cat_audio,
            detail: Copy.fill2(Copy.cleanup_media_detail, `${this.t.audioFiles}`,
              humanBytes(this.t.audioBytes)),
            available: this.t.audioFiles > 0,
            on: this.isOn('audio'),
            expandable: this.t.audioFiles > 0,
            open: this.isOpen('audio'),
            onPick: (on: boolean): void => {
              this.setKind('audio', on);
            },
            onToggle: (): void => {
              this.toggleOpen('audio');
            }
          })
          this.fileList('audio')
          CleanupRow({
            label: Copy.cleanup_cat_doc,
            detail: Copy.fill2(Copy.cleanup_media_detail, `${this.t.docFiles}`,
              humanBytes(this.t.docBytes)),
            available: this.t.docFiles > 0,
            on: this.isOn('doc'),
            expandable: this.t.docFiles > 0,
            open: this.isOpen('doc'),
            onPick: (on: boolean): void => {
              this.setKind('doc', on);
            },
            onToggle: (): void => {
              this.toggleOpen('doc');
            }
          })
          this.fileList('doc')
          CleanupRow({
            label: Copy.cleanup_cat_record,
            detail: Copy.fill2(Copy.cleanup_media_detail, `${this.t.recordFiles}`,
              humanBytes(this.t.recordBytes)),
            available: this.t.recordFiles > 0,
            on: this.isOn('record'),
            expandable: this.t.recordFiles > 0,
            open: this.isOpen('record'),
            onPick: (on: boolean): void => {
              this.setKind('record', on);
            },
            onToggle: (): void => {
              this.toggleOpen('record');
            }
          })
          this.fileList('record')
          CleanupRow({
            label: Copy.cleanup_cat_other,
            detail: Copy.fill2(Copy.cleanup_media_detail, `${this.t.otherFiles}`,
              humanBytes(this.t.otherBytes)),
            available: this.t.otherFiles > 0,
            on: this.isOn('other'),
            expandable: this.t.otherFiles > 0,
            open: this.isOpen('other'),
            onPick: (on: boolean): void => {
              this.setKind('other', on);
            },
            onToggle: (): void => {
              this.toggleOpen('other');
            }
          })
          this.fileList('other')

          CleanupRow({
            label: Copy.cleanup_cat_choices,
            detail: Copy.fillN(Copy.cleanup_choice_detail, this.t.choices),
            available: this.t.choices > 0,
            on: this.onChoices,
            expandable: false,
            open: false,
            onPick: (on: boolean): void => {
              this.onChoices = on;
            }
          })

          if (this.notice.length > 0) {
            Text(this.notice)
              .fontSize(AppType.caption)
              .fontColor(AppColor.warning_text)
              .width(AppMeasure.panel(this.wBp))
          }

          AppButton({
            label: this.pickedCount() > 0 ? Copy.fillN(Copy.cleanup_go, this.pickedCount())
              : Copy.cleanup_selected_none,
            disabled: this.pickedCount() === 0 || this.busy,
            grow: true,
            onTap: (): void => {
              this.confirming = true;
            }
          })
        }
        .width('100%')
        .padding({
          left: AppSpace.lg,
          right: AppSpace.lg,
          bottom: AppSpace.lg
        })
      }
      /** Scroll centres its child by default; a short list would float mid-screen. */
      .align(Alignment.Top)
      .width('100%')
      .height('100%')

      if (this.confirming) {
        this.confirmSheet()
      }

      if (this.watchPath.length > 0) {
        this.watchSheet()
      }

      if (this.readPath.length > 0) {
        this.readSheet()
      }
    }
    .alignContent(Alignment.Center)
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bg)
  }
}
