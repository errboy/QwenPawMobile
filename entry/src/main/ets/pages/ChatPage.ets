/**
 * One chat window.
 *
 * The page is a mirror of ChatStore: it registers the store with the app-wide
 * poller, re-renders when the store emits, and forwards taps back. All run
 * scheduling, frame merging and reconnect policy live behind the store.
 */
import { common } from '@kit.AbilityKit';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { Bubble } from '../ui/chat/Bubble';
import { ApprovalCard } from '../ui/chat/ApprovalCard';
import { Composer } from '../ui/chat/Composer';
import { AppColor, AppMotion, AppRadius, AppSize, AppSpace, AppType } from '../theme/Theme';
import { Copy } from '../l10n/Copy';
import { Attachment } from '../model/Attachment';
import { ApprovalInfo, ChatRef, ChatSpec } from '../model/Dtos';
import { Role } from '../core/Wire';
import { Failure } from '../core/Failure';
import { UiMessage } from '../state/UiMessage';
import { ChatStore } from '../state/ChatStore';
import { RunPhase } from '../stream/RunController';
import { StoreHub } from '../state/StoreHub';

@Entry
@Component
struct ChatPage {
  @State items: UiMessage[] = [];
  @State approvals: ApprovalInfo[] = [];
  @State bgRunning: ChatSpec[] = [];
  /** Other sessions stay one tap away but out of the way: collapsed by default. */
  @State bgPanelOpen: boolean = false;
  @State inputText: string = '';
  @State pending: Attachment[] = [];
  @State busy: boolean = false;
  @State loadingHistory: boolean = true;
  @State uploading: boolean = false;
  @State title: string = '';
  @State generating: boolean = false;
  @State nowSec: number = 0;
  private ref: ChatRef = new ChatRef();
  private store: ChatStore | undefined = undefined;
  private pull: () => void = (): void => {};
  private scroller: Scroller = new Scroller();
  private lastCount: number = 0;
  private lastTailLength: number = 0;
  private lastMediaRev: number = 0;

  private hub(): StoreHub {
    return StoreHub.shared();
  }

  private ctx(): common.Context | undefined {
    return this.getUIContext().getHostContext() as common.Context | undefined;
  }

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    const raw: Object | undefined = this.getUIContext().getRouter().getParams();
    if (raw !== undefined) {
      const params = raw as ChatRef;
      if (params.chatId.length > 0) {
        this.ref = params;
      }
    }
    if (this.ref.chatId.length === 0) {
      const saved = this.hub().app.foreground;
      if (saved !== undefined) {
        this.ref = saved;
      }
    }
    this.title = this.ref.title.length > 0 ? this.ref.title : Copy.chat_default_title;
    const store = this.hub().chatStoreFor(this.ref);
    this.store = store;
    this.pull = (): void => {
      this.sync();
    };
    store.attachView(this.pull);
    this.hub().poller.register(store);
    this.sync();
    store.bootstrap();
  }

  aboutToDisappear(): void {
    const store = this.store;
    if (store === undefined) {
      return;
    }
    // The store itself stays in the hub: a run started here must survive the pop.
    this.hub().poller.unregister(store);
    store.detachView(this.pull);
  }

  private sync(): void {
    const store = this.store;
    if (store === undefined) {
      return;
    }
    this.items = store.items;
    this.approvals = store.approvals;
    this.bgRunning = store.bgRunning;
    this.loadingHistory = store.loading;
    this.uploading = store.uploading;
    this.busy = store.busy();
    this.nowSec = store.nowSec;
    this.generating = store.phase !== RunPhase.IDLE;
    this.followTail(store.mediaRev);
  }

  /** Stick to the bottom when a bubble is added or the last one keeps growing. */
  private followTail(mediaRev: number): void {
    const count = this.items.length;
    const tail = count > 0 ? this.items[count - 1].text.length : 0;
    const settled = mediaRev !== this.lastMediaRev;
    if (count === this.lastCount && tail === this.lastTailLength && !settled) {
      return;
    }
    this.lastCount = count;
    this.lastTailLength = tail;
    this.lastMediaRev = mediaRev;
    // Scrolling in this frame measures the list as it was before the state
    // flush, so a freshly loaded history would jump back to the top.
    // A decoded image grows its bubble one layout pass later, so that jump has
    // to wait for the new height instead of measuring the pre-image list.
    this.stickTail(settled ? AppMotion.state : 0);
  }

  private stickTail(delay: number): void {
    setTimeout((): void => {
      this.scroller.scrollEdge(Edge.End);
    }, delay);
  }

  private send(): void {
    const store = this.store;
    if (store === undefined) {
      return;
    }
    const text = this.inputText;
    const files = this.pending;
    this.inputText = '';
    this.pending = [];
    store.send(text, files);
  }

  private pick(fromGallery: boolean): void {
    if (this.uploading) {
      return;
    }
    const api = this.hub().uploadApi;
    const append = (list: Attachment[]): void => {
      if (list.length === 0) {
        return;
      }
      this.pending = this.pending.concat(list);
    };
    const failed = (e: Object): void => {
      // Backing out of the picker rejects with a "cancel" message; that is the
      // user's choice, not a failure to report.
      const detail = Failure.from(e).message;
      const store = this.store;
      if (store !== undefined && detail.length > 0 && !detail.includes('cancel')) {
        store.reportPickFailure(detail);
      }
    };
    if (fromGallery) {
      api.pickImages().then(append).catch(failed);
    } else {
      api.pickFiles().then(append).catch(failed);
    }
  }

  private remove(key: string): void {
    this.pending = this.pending.filter((a: Attachment): boolean => a.key !== key);
  }

  private recall(key: string): void {
    const store = this.store;
    if (store !== undefined) {
      store.recallQueued(key);
    }
  }

  private decide(approval: ApprovalInfo, approved: boolean): void {
    const store = this.store;
    if (store !== undefined) {
      store.decide(approval, approved);
    }
  }

  private goBack(): void {
    this.getUIContext().getRouter().back();
  }

  /** Switching windows pushes a second page; the first keeps its live run. */
  private openAnother(chat: ChatSpec): void {
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

  @Builder
  header() {
    Column({ space: AppSpace.xxs }) {
      Row({ space: AppSpace.sm }) {
        Text(Copy.chat_back)
          .fontSize(AppType.body)
          .fontColor(AppColor.accent_text)
          .padding({ top: AppSpace.sm, bottom: AppSpace.sm })
          .onClick(() => {
            this.goBack();
          })
        Text(this.title)
          .fontSize(AppType.subtitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.generating) {
          Text(Copy.chat_generating)
            .fontSize(AppType.caption)
            .fontColor(AppColor.success)
        }
      }
      .width('100%')

      if (this.bgRunning.length > 0) {
        Row({ space: AppSpace.xs }) {
          Text(Copy.fillN(Copy.chat_bg_sessions, this.bgRunning.length))
            .fontSize(AppType.caption)
            .fontColor(AppColor.text_tertiary)
          Blank()
          Text(this.bgPanelOpen ? Copy.home_group_collapse : Copy.home_group_expand)
            .fontSize(AppType.caption)
            .fontColor(AppColor.accent_text)
        }
        .width('100%')
        .padding({ top: AppSpace.xxs, bottom: AppSpace.xxs })
        .onClick(() => {
          this.bgPanelOpen = !this.bgPanelOpen;
        })

        if (this.bgPanelOpen) {
          Row({ space: AppSpace.xs }) {
            ForEach(this.bgRunning, (chat: ChatSpec) => {
              Text(`${chat.name} ${Copy.chat_open}`)
                .fontSize(AppType.caption)
                .fontColor(AppColor.accent_text)
                .backgroundColor(AppColor.accent_faint)
                .borderRadius(AppRadius.pill)
                .padding({ left: AppSpace.sm, right: AppSpace.sm, top: AppSpace.xxs, bottom: AppSpace.xxs })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .onClick(() => {
                  this.openAnother(chat);
                })
            }, (chat: ChatSpec): string => `${chat.id}_${chat.status}`)
          }
          .width('100%')
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: AppSpace.sm, bottom: AppSpace.xs })
  }

  @Builder
  bubbleRow(item: UiMessage) {
    Row() {
      if (item.role === Role.USER) {
        Blank()
      }
      Bubble({
        item: item,
        onRecall: (key: string): void => {
          this.recall(key);
        }
      })
      if (item.role !== Role.USER) {
        Blank()
      }
    }
    .width('100%')
  }

  build() {
    Column({ space: AppSpace.xxs }) {
      this.header()

      if (this.loadingHistory) {
        Text(Copy.chat_loading_history)
          .fontSize(AppType.body)
          .fontColor(AppColor.text_secondary)
          .width('100%')
      } else {
        // List.space takes number|string only, so the gap comes from item margins.
        List({ scroller: this.scroller }) {
          ForEach(this.items, (item: UiMessage) => {
            ListItem() {
              this.bubbleRow(item)
            }
            .margin({ bottom: AppSpace.xs })
          }, (item: UiMessage): string => item.key)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onAppear((): void => {
          // A page pushed onto an already-loaded history has nothing to measure
          // during its state flush; the tail jump belongs here.
          this.stickTail(0);
        })
      }

      ForEach(this.approvals, (approval: ApprovalInfo) => {
        ApprovalCard({
          approval: approval,
          nowSec: this.nowSec,
          onDecide: (target: ApprovalInfo, approved: boolean): void => {
            this.decide(target, approved);
          }
        })
      }, (approval: ApprovalInfo): string => `${approval.request_id}_${this.nowSec}`)

      Composer({
        text: $inputText,
        attachments: $pending,
        busy: this.busy,
        uploading: this.uploading,
        onSend: (): void => {
          this.send();
        },
        onStop: (): void => {
          const store = this.store;
          if (store !== undefined) {
            store.stopRun();
          }
        },
        onPick: (fromGallery: boolean): void => {
          this.pick(fromGallery);
        },
        onRemove: (key: string): void => {
          this.remove(key);
        }
      })

      if (this.uploading) {
        Row({ space: AppSpace.xs }) {
          LoadingProgress()
            .width(AppSize.icon_md)
            .height(AppSize.icon_md)
            .color(AppColor.accent)
          Text(Copy.notice_uploading)
            .fontSize(AppType.caption)
            .fontColor(AppColor.text_tertiary)
        }
        .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: AppSpace.md, right: AppSpace.md })
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bg)
  }
}
