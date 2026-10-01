/**
 * Channel grouping for the window list.
 *
 * A phone screen shows four or five chats at a time, but one agent can have
 * dozens across console, WeChat and Feishu. Grouping by channel and collapsing
 * what is not running is what keeps the list scannable; running chats sort first
 * because they are the ones that might need an answer.
 */
import { ChatSpec } from '../../model/Dtos';
import { ChatStatus } from '../../core/Wire';
import { Copy } from '../../l10n/Copy';

export class ChannelGroup {
  key: string = '';
  icon: string = '';
  label: string = '';

  constructor(key: string, icon: string, label: string) {
    this.key = key;
    this.icon = icon;
    this.label = label;
  }
}

export class ChannelGroups {
  static readonly CONSOLE: ChannelGroup = new ChannelGroup('console', '💻', Copy.home_group_console);
  static readonly WECHAT: ChannelGroup = new ChannelGroup('wechat', '💬', Copy.home_group_wechat);
  static readonly FEISHU: ChannelGroup = new ChannelGroup('feishu', '📮', Copy.home_group_feishu);
  static readonly OTHER: ChannelGroup = new ChannelGroup('other', '🔌', Copy.home_group_other);

  static all(): ChannelGroup[] {
    return [ChannelGroups.CONSOLE, ChannelGroups.WECHAT, ChannelGroups.FEISHU, ChannelGroups.OTHER];
  }

  static of(channel: string): ChannelGroup {
    if (channel === 'wechat') {
      return ChannelGroups.WECHAT;
    }
    if (channel === 'feishu') {
      return ChannelGroups.FEISHU;
    }
    if (channel === 'console') {
      return ChannelGroups.CONSOLE;
    }
    return ChannelGroups.OTHER;
  }

  /** Group members except the pinned foreground chat, running first. */
  static chatsIn(chats: ChatSpec[], group: ChannelGroup, excludeId: string): ChatSpec[] {
    const out: ChatSpec[] = [];
    for (const c of chats) {
      if (c.id !== excludeId && ChannelGroups.of(c.channel).key === group.key) {
        out.push(c);
      }
    }
    out.sort((a: ChatSpec, b: ChatSpec): number => {
      const aRunning = a.status === ChatStatus.RUNNING;
      const bRunning = b.status === ChatStatus.RUNNING;
      if (aRunning !== bRunning) {
        return aRunning ? -1 : 1;
      }
      return b.updated_at.localeCompare(a.updated_at);
    });
    return out;
  }

  static runningIn(chats: ChatSpec[], group: ChannelGroup, excludeId: string): number {
    let n = 0;
    for (const c of ChannelGroups.chatsIn(chats, group, excludeId)) {
      if (c.status === ChatStatus.RUNNING) {
        n += 1;
      }
    }
    return n;
  }
}
