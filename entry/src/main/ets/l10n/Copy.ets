/**
 * Every user-visible string in the app, in one place.
 * Templates use %s / %d and are expanded by Copy.fill().
 */

export class Copy {
  static readonly app_name: string = 'QwenPaw Mobile';
  static readonly theme_system: string = '跟随系统';
  static readonly theme_light: string = '浅色';
  static readonly theme_dark: string = '深色';

  // ---------- sign in ----------
  static readonly username_field: string = '用户名';
  static readonly username_placeholder: string = '服务器未启用认证时可留空';
  static readonly password_field: string = '密码';
  static readonly password_placeholder: string = '可选';
  static readonly action_use_saved: string = '使用已保存的登录进入';
  static readonly need_server_address: string = '请输入服务器地址，例如 http://192.168.1.100:8088';
  static readonly connecting: string = '正在连接…';
  static readonly bad_credentials: string = '用户名或密码错误';
  static readonly account_locked: string = '尝试过于频繁，账号暂时锁定';
  /**
   * Any other server verdict at sign-in. The tail is the diagnostic, which the
   * user can read out to whoever runs the PC: the server's own sentence when it
   * sent one, otherwise an HTTP status and path. The wrapper keeps the line
   * Chinese either way.
   */
  static readonly login_failed: string = '登录失败：%s';

  // ---------- sign in: pick a server ----------
  static readonly login_pick_hint: string = '点选一个在线地址，登录会使用配置页里的用户名和密码';
  static readonly login_saved_section: string = '已配置的地址';
  static readonly login_found_section: string = '局域网中发现';
  static readonly login_empty: string = '还没有可用地址。打开“登录配置”手动添加，或直接扫描局域网。';
  static readonly login_none_found: string = '扫描完成，这一网段没有发现 QwenPaw 服务';
  static readonly login_no_network: string = '手机当前不在局域网 Wi-Fi 上，无法扫描';
  static readonly action_scan: string = '扫描局域网';
  static readonly action_scanning: string = '扫描中…';
  static readonly action_login: string = '登录';
  static readonly action_login_busy: string = '登录中…';
  static readonly action_open_config: string = '登录配置';
  static readonly need_selection: string = '请先在列表里点选一个服务器地址';
  static readonly login_selected: string = '已选择: %s';
  static readonly login_scan_progress: string = '已检查 %d/%d · 发现 %d 台';
  static readonly login_status_offline: string = '无响应';
  static readonly login_status_unprobed: string = '未探测';
  static readonly login_auth_required: string = '需登录';
  static readonly login_auth_open: string = '免认证';
  static readonly login_latency: string = '%dms';

  // ---------- login configuration page ----------
  static readonly config_title: string = '登录配置';
  static readonly config_back: string = '‹ 返回登录';
  static readonly config_servers_label: string = '服务器地址列表';
  static readonly config_server_hint: string = '可只填 IP，端口留空则用下方扫描端口';
  static readonly config_new_placeholder: string = '192.168.1.23 或 http://192.168.1.23:8088';
  static readonly config_add: string = '添加';
  static readonly config_delete: string = '删除';
  static readonly config_port_label: string = '端口';
  static readonly config_port_hint: string = '扫描端口，默认 8088';
  static readonly config_credential_label: string = '登录凭据';
  static readonly config_credential_hint: string = '保存在本机，登录页直接使用';
  static readonly config_local_address: string = '手机本机地址: %s';
  static readonly config_local_unknown: string = '未读到本机地址，可能没有联网';
  static readonly config_scan_range: string = '扫描范围: %s.1 – %s.254';
  static readonly config_save: string = '保存并返回';
  static readonly config_duplicate: string = '这个地址已经在列表里了';
  static readonly config_invalid: string = '地址格式不正确';
  static readonly config_empty_list: string = '列表为空，登录页将没有可选地址';
  static readonly config_saved_line: string = '已保存 %d 个地址 · 端口 %d';

  // ---------- home ----------
  static readonly home_title: string = 'QwenPaw 会话';
  static readonly home_logout: string = '退出';
  static readonly home_server_line: string = '服务器: %s';
  static readonly home_user_line: string = '用户: %s';
  static readonly home_no_auth_user: string = '(无认证)';
  static readonly home_agent_label: string = '智能体';
  static readonly home_foreground_badge: string = '▶ 主会话';
  static readonly home_foreground_hint: string = '默认是你上次使用的会话 · 长按其他会话可切换';
  static readonly home_resume: string = '继续 ›';
  static readonly home_running_chip: string = '⏳ 进行中';
  static readonly home_approvals: string = '🔒 %d 项待审批';
  static readonly home_bg_running: string = '⏳ %d 个会话进行中';
  /** Phone-side view switch: hide every window but the main one. */
  static readonly home_only_main: string = '只看主会话';
  static readonly home_show_all: string = '显示全部会话';
  static readonly home_collapsed_hint: string = '已收起 %d 个会话';
  static readonly home_empty: string = '暂无会话。点下方“新建会话”，或在电脑端 Console 发起对话后同步到这里。';
  static readonly home_offline: string = '⚠ 无法连接服务器，列表可能已过期';
  /**
   * Shown instead of `home_offline` when the server answers but refuses the
   * token. Naming the fix matters: retrying a 401 never succeeds, so the only
   * way back is signing in again — which is what tapping this line does.
   */
  static readonly home_session_expired: string = '⚠ 登录已失效，点按重新登录';
  static readonly home_refresh: string = '刷新会话列表';
  static readonly home_group_console: string = '控制台会话';
  /** Start a window from the phone; the server still mints its id. */
  static readonly home_new_chat: string = '新建会话';
  static readonly chat_new_title: string = '新会话';
  static readonly notice_new_chat_failed: string = '新建会话失败：%s';
  static readonly home_group_wechat: string = '微信机器人';
  static readonly home_group_feishu: string = '飞书机器人';
  static readonly home_group_other: string = '其他渠道';
  static readonly home_group_count: string = '%s %s · %d';
  static readonly home_group_running: string = '⏳ %d 进行中';
  static readonly home_group_expand: string = '▾ 展开';
  static readonly home_group_collapse: string = '▴ 收起';
  static readonly home_row_running: string = '进行中';
  /** Opens the three-way picker; the current mode is shown by its tick. */
  static readonly home_theme: string = '主题 ▾';
  static readonly home_row_meta: string = '%s · %s';
  /** Local-only storage line: what this phone holds, never the server's record. */
  static readonly home_storage_line: string = '媒体缓存 %s · 未发送草稿 %d 条';
  static readonly home_storage_note: string = '聊天记录保存在电脑端，这里只清理手机上的副本';
  static readonly home_storage_clear: string = '清理';

  // ---------- cleanup ----------
  /** A page, not a tap: each kind of residue has a different cost to undo. */
  static readonly cleanup_title: string = '清理本机数据';
  static readonly cleanup_note: string =
    '这里只删手机上的副本。图片从不落到手机存储，「下载」的东西在系统相册里、由相册管；'
    + '聊天记录和文件本体都在电脑端，手机上删不掉，也不必删。';
  /** The cache buckets, named by what the user did to fill them. */
  static readonly cleanup_cat_video: string = '看过的视频';
  static readonly cleanup_cat_audio: string = '听过的音频';
  static readonly cleanup_cat_doc: string = '打开过的文档';
  static readonly cleanup_cat_record: string = '录的音（发出去也留着）';
  static readonly cleanup_cat_other: string = '其他缓存';
  static readonly cleanup_cat_choices: string = '会话偏好（模型 / 审批 / loop / 发过的媒体）';
  static readonly cleanup_media_detail: string = '%s 个文件 · %s';
  static readonly cleanup_choice_detail: string = '%d 个会话';
  static readonly cleanup_nothing: string = '没有可清的';
  /**
   * Opening a row lists its copies, so one of them can be left alone. The arrow is
   * the tier marker: the list it opens is a child of this row, not another row.
   */
  static readonly cleanup_items: string = '▾ 逐条';
  static readonly cleanup_items_close: string = '▴ 收起';
  /** Second line of a row: size and last write, under the name line. */
  static readonly cleanup_file_detail: string = '%s · %s';
  /** Partial picks are named by how many go, not by the category alone. */
  static readonly cleanup_summary_part: string = '%s（只删其中 %d 个）';
  /** Shown instead of an all-empty list when the device itself could not be read. */
  static readonly cleanup_read_failed: string = '读不到本机数据：%s';
  /** One button for both directions; the ticks below it are the feedback. */
  static readonly cleanup_go_all: string = '全选 / 全不选';
  static readonly cleanup_selected_none: string = '未选中任何一项';
  static readonly cleanup_go: string = '清理所选 · %d 项';
  static readonly cleanup_confirm_title: string = '确认清理';
  /** Names the categories, because an unchecked list is how data goes missing. */
  static readonly cleanup_confirm_body: string =
    '将永久删除手机上的：%s。缓存的下次打开会重新下载，会话偏好要重新选，无法撤销。';
  static readonly cleanup_confirm_yes: string = '确认清理';
  static readonly cleanup_done: string = '已清理 %d 项';
  /** A text document longer than the preview reads: the top is shown, and said so. */
  static readonly cleanup_read_truncated: string = '只显示开头 %s';

  // ---------- chat ----------
  static readonly chat_back: string = '‹ 返回';
  static readonly chat_default_title: string = '对话';
  static readonly chat_generating: string = '● 生成中';
  static readonly chat_bg_sessions: string = '⏳ %d 个后台会话进行中';
  static readonly chat_open: string = '查看 ›';
  static readonly chat_loading_history: string = '加载历史消息…';
  static readonly chat_input_placeholder: string = '发消息…';
  static readonly chat_input_busy: string = '发送将打断当前生成…';
  static readonly chat_stop: string = '停止';
  static readonly chat_send: string = '发送并插队';
  static readonly chat_send_idle: string = '发送';
  static readonly cancel: string = '取消';
  static readonly send: string = '发送';
  static readonly editor_title: string = '编辑消息';
  static readonly chat_queued_hint: string = '排队中 · 点我撤回';
  /**
   * A send whose POST came back without ever opening a stream: the server never
   * took the message, and the history rebuild that follows would otherwise erase
   * the bubble as though it had gone out.
   */
  static readonly chat_undelivered: string = '未送达';
  static readonly notice_undelivered: string = '这条没有发到服务器，长按它可以引用重发';
  static readonly chat_attach_gallery: string = '🖼 相册（图片/视频）';
  static readonly chat_attach_files: string = '📄 手机文件';
  static readonly chat_attach_audio: string = '🎵 音频';
  /** Starts a recording; stopping it is the recording bar's job, not this row's. */
  static readonly chat_attach_record: string = '🎙 录一段语音';
  /**
   * Composer mode switch. Speech-to-text is deliberately not implemented here:
   * the IME already dictates, so the voice mode only covers the case the
   * keyboard cannot — sending the audio itself.
   */
  /** The composer's two mode glyphs: A for audio, T for text — the mode the tap lands in. */
  static readonly chat_mode_voice: string = 'A';
  static readonly chat_mode_text: string = 'T';
  /** Voice mode is hold-to-talk: press to record, release to send, slide up to drop. */
  static readonly chat_voice_idle: string = '按住 说话';
  static readonly chat_voice_release: string = '松开发送';
  static readonly chat_voice_cancel: string = '松开取消';
  static readonly chat_long_text: string = '📝 长文本';
  /**
   * ＋ menu: one row for the skill picker, one for the MCP inventory. A skill runs by
   * its name reaching the message text, so picking one is a shortcut for typing
   * `/name` — the form the server dispatches on, not a label of our own invention.
   * The skills themselves moved out of the menu into SkillPanel: a real desktop has
   * more of them than a menu has room, and each row needs its description to be
   * worth tapping. The empty row is switched off, and says 可用 rather than 已启用
   * because a failed read lands here too — the row can name what the menu has, not why.
   * The two rows carry 电脑 as a suffix instead of a 电脑端的 prefix: the menu is a list
   * of sources, and a shorter tail keeps both rows on one line. The panels they open
   * keep the long title, because there the phone/computer split is the thing being read.
   */
  static readonly chat_attach_skills: string = '🧩 技能 (电脑)';
  static readonly chat_attach_skill_none: string = '🧩 电脑端没有可用的技能';
  static readonly skills_title: string = '电脑端的技能';
  static readonly skills_note: string = '点一条把 /技能名 写进消息框；开关技能在电脑端';
  static readonly skills_empty: string = '电脑端没有可用的技能';
  static readonly skills_close: string = '关闭';
  static readonly chat_attach_mcp: string = '🔌 MCP (电脑)';
  static readonly mcp_title: string = '电脑端的 MCP';
  static readonly mcp_note: string = '只读：手机上不能开关客户端，也不能改它的工具';
  static readonly mcp_empty: string = '电脑端没有配置 MCP 客户端';
  static readonly mcp_failed: string = '读不到电脑端的 MCP：%s';
  static readonly mcp_off: string = '已停用';
  static readonly mcp_tools_loading: string = '正在读工具…';
  static readonly mcp_tools_failed: string = '读不到工具：%s';
  /** A stopped client answers with an empty tool list, which is not the same fact. */
  static readonly mcp_tools_stopped: string = '客户端已停用，读不到工具';
  static readonly mcp_tools_empty: string = '这个客户端没有暴露工具';
  static readonly mcp_close: string = '关闭';
  /** Long-press a bubble: put that message into the composer instead of retyping it. */
  static readonly chat_quote_text: string = '引用这段文字';
  /**
   * Copy is the raw text of the bubble, markdown markers included, so pasting it
   * elsewhere rebuilds the same heading, list and table the bubble draws.
   */
  static readonly chat_copy_text: string = '复制这段文字';
  static readonly chat_copied: string = '已复制';
  static readonly chat_copy_failed: string = '复制失败';
  static readonly chat_quote_image: string = '引用这张图片';
  static readonly chat_quote_video: string = '引用这段视频';
  static readonly chat_quote_audio: string = '引用这段语音';
  static readonly chat_quote_file: string = '引用这个文件';
  /** Tray chip prefix: the bytes are already on the server, so sending uploads nothing. */
  static readonly chat_quoted_prefix: string = '↩ %s';
  /**
   * Trailing line when a quote hit QUOTE_MAX: %s is the file the whole message
   * goes out as, %d its real length. The paste stays a preview because the
   * transcript must still show what is being quoted; the file carries the rest.
   */
  static readonly chat_quote_as_file: string = '（这段太长，上面只是开头；完整原文随这条消息以 %s 发出，共 %d 字）';
  /** Header entry point into this chat's asset list; %d is how many there are. */
  static readonly assets_entry: string = '📁 %d';
  static readonly assets_title: string = '本会话的文件与多媒体';
  static readonly assets_note: string = '转录存在电脑端，这里只列本会话收发过的文件与多媒体';
  static readonly assets_empty: string = '这个会话还没有文件或多媒体';
  static readonly assets_close: string = '关闭';
  static readonly assets_kind_image: string = '🖼 图片';
  static readonly assets_kind_video: string = '🎬 视频';
  static readonly assets_kind_audio: string = '🔊 语音';
  static readonly assets_kind_file: string = '📄 文件';
  /** A row whose bytes are on the phone says how many; the rest live only on the PC. */
  static readonly assets_local: string = '本机 %s';
  static readonly assets_remote: string = '仅电脑端';
  /** Cue on the row's name line, which is the tap target that opens the asset. */
  static readonly assets_open: string = '打开 ›';
  static readonly assets_locate: string = '定位';
  static readonly assets_save: string = '下载';
  static readonly assets_forward: string = '转发';
  static readonly assets_drop: string = '删除副本';
  static readonly assets_busy: string = '正在取字节…';
  static readonly assets_dropped: string = '已删除本机副本';
  static readonly assets_fetch_failed: string = '没能取回 %s 的字节';
  static readonly assets_drop_failed: string = '这个副本正被占用，未能删除';
  static readonly assets_drop_gone: string = '本机已经没有这一份了，不需要再删';
  static readonly assets_drop_title: string = '删除手机上的这一份？';
  static readonly assets_drop_body: string = '只删手机上的副本：%s。电脑端那一份不受影响，下次打开会重新取一次。';
  /** Export outcomes. Backing out of a system dialog is not a failure, so it says nothing. */
  static readonly export_saved_gallery: string = '已保存到相册';
  static readonly export_saved: string = '已保存';
  static readonly export_save_failed: string = '保存失败：%s';
  static readonly export_share_failed: string = '转发失败：%s';
  static readonly export_no_ext: string = '这个文件没有扩展名，系统判断不了类型，未能转发';
  static readonly export_unknown_type: string = '不认识的 .%s 类型，未能转发';
  /** startAbility's own error is a code and an English sentence; the user gets the reason. */
  static readonly export_open_failed: string = '这台手机上没有能打开它的已装应用';
  static readonly chat_recording: string = '录音中 %s';
  static readonly chat_rec_stop: string = '停止录音';
  static readonly chat_rec_cancel: string = '丢弃';
  static readonly notice_voice_denied: string = '没有麦克风权限，无法录音';
  static readonly notice_voice_failed: string = '录音失败：%s';
  static readonly notice_voice_code: string = '录音失败（错误码 %d）';
  static readonly notice_voice_none: string = '没有进行中的录音';
  static readonly notice_voice_empty: string = '录音是空的，没有附上文件';
  static readonly chat_reasoning_label: string = '💭 深度思考';
  /** The reasoning block follows the run, so the cue says which way this tap goes. */
  static readonly chat_reasoning_expand: string = '▾ 看想法';
  static readonly chat_reasoning_collapse: string = '▴ 收起';
  static readonly chat_tool_label: string = '🔧 %s';
  /**
   * A card that handed over a file is titled by that file, not by the tool: a row of
   * `🔧 send_file_to_user` cards is unreadable at a glance, and the name is what the
   * user scrolls to find. The tool's own name stays under it, so nothing is hidden.
   */
  static readonly chat_tool_delivery: string = '📁 %s';
  static readonly chat_tool_output_suffix: string = ' · 输出';
  /** A tool card arrives folded; the cue says which way this tap takes it. */
  static readonly chat_tool_expand: string = '▾ 看详情';
  static readonly chat_tool_collapse: string = '▴ 收起';
  /** A run of tool cards folds behind one line; the count is what unfolds below it. */
  static readonly chat_tool_group: string = '🔧 工具卡 ×%d';
  static readonly chat_default_tool_name: string = '工具';
  static readonly chat_part_image: string = '[图片]';
  static readonly chat_part_video: string = '[视频]';
  static readonly chat_part_audio: string = '[语音]';
  static readonly chat_part_file: string = '[文件: %s]';
  static readonly chat_image_loading: string = '加载图片…';
  static readonly chat_image_unavailable: string = '图片暂不可用';
  /** The whole full-screen image is the close gesture, so the hint has to say so. */
  static readonly chat_zoom_close: string = '点击任意处关闭';
  static readonly chat_video_loading: string = '加载视频…';
  static readonly chat_video_unavailable: string = '视频暂不可用';
  static readonly chat_audio_label: string = '🎤 语音消息';
  /** Tap-to-play chip: there is no waveform here, so the label carries the state. */
  static readonly chat_audio_playing: string = '⏸ 播放中 · 点击停止';
  static readonly notice_audio_failed: string = '语音播放失败：%s';
  static readonly chat_audio_unavailable: string = '语音暂不可用';
  static readonly chat_file_unavailable: string = '文件暂不可用';
  /**
   * Name for a file the tool inlined without naming it. There is no path to read a
   * leaf off, so the bubble would otherwise show the tail of a base64 payload.
   */
  static readonly chat_file_inline: string = '内嵌文件';
  /** Second line of a file bubble: what kind of file it is, then where the bytes are. */
  static readonly chat_file_kind: string = '%s 文件';
  static readonly chat_file_kind_unknown: string = '未知类型';
  static readonly chat_file_meta: string = '%s · %s';
  /** The bytes live on the PC, so opening one costs a fetch before an app ever sees it. */
  static readonly chat_file_opening: string = '正在取字节…';
  static readonly chat_file_view: string = '查看 ›';
  /** Chip label when no loop mode is chosen; the server's default mode has no command. */
  static readonly chat_loop_none: string = '默认模式';
  /** Model label when the phone sends no override, so the PC agent's slot answers. */
  static readonly chat_model_follow: string = '电脑端默认';
  /**
   * Approval levels, word for word the names the PC console's zh locale uses for
   * the same four values, so both screens describe one setting.
   */
  static readonly chat_approval_follow: string = '电脑端默认';
  static readonly chat_approval_strict: string = '严格模式';
  static readonly chat_approval_smart: string = '智能模式';
  static readonly chat_approval_auto: string = '自动模式';
  static readonly chat_approval_off: string = '关闭模式';

  // ---------- slash menu: group headers ----------
  static readonly slash_group_builtin: string = '内置';
  static readonly slash_group_conversation: string = '会话';
  static readonly slash_group_control: string = '控制';
  static readonly slash_group_daemon: string = '后台';
  static readonly slash_group_skill: string = '技能';
  static readonly slash_group_auto: string = '自动';
  static readonly slash_group_user: string = '自定义';
  static readonly slash_group_mode: string = '模式';
  static readonly slash_group_loop: string = '循环模式';
  static readonly slash_group_plugin: string = '插件';
  static readonly slash_group_other: string = '其他';

  // ---------- approvals ----------
  static readonly approval_headline: string = '⛔ %s';
  static readonly approval_meta: string = '%s · %s后超时';
  static readonly approval_timeout_in: string = '%d秒';
  static readonly approval_note: string = '任务已暂停，等待你的决定';
  static readonly approval_approve: string = '批准执行';
  static readonly approval_deny: string = '拒绝';
  static readonly approval_denied_reason: string = '用户在手机端拒绝';
  static readonly approval_approved: string = '✅ %s';
  static readonly approval_denied: string = '❌ 已拒绝：%s';

  // ---------- notices ----------
  static readonly notice_history_failed: string = '加载历史失败：%s';
  static readonly notice_interrupted: string = '连接中断，%d 秒后自动重连…';
  static readonly notice_interrupted_with: string = '连接中断（%s），%d 秒后自动重连…';
  static readonly notice_reconnect_failed: string = '重连失败。后台仍在生成时会自动继续探测，稍后可看到最新内容';
  static readonly notice_generation_failed: string = '生成失败：%s';
  static readonly notice_stopped: string = '已停止生成';
  static readonly notice_unknown_error: string = '未知错误';
  static readonly notice_upload_failed: string = '上传失败：%s';
  static readonly notice_clear_failed: string = '清理失败：%s';
  static readonly notice_upload_no_path: string = '上传响应缺少文件路径';
  static readonly notice_chat_no_id: string = '新建会话响应缺少 id';
  static readonly notice_history_empty: string = '历史记录响应为空';
  static readonly notice_no_base_url: string = '服务器地址未配置';
  /**
   * A list endpoint answered 200 with something that is not a list. Only a
   * proxy or a gateway can do this to us; the path is the half the reader
   * needs to say which one.
   */
  static readonly notice_not_a_list: string = '%s 返回的不是一份列表';
  static readonly notice_pick_failed: string = '选择文件失败：%s';
  static readonly notice_pick_skipped: string = '已跳过：%s';
  static readonly notice_file_too_large: string = '%s 超过 %dMB 上限';
  static readonly notice_file_unreadable: string = '无法读取文件 %s';
  static readonly notice_file_truncated: string = '文件 %s 读取中断';
  static readonly notice_stop_failed: string = '停止失败：%s';
  static readonly notice_approval_failed: string = '审批操作失败：%s';
  static readonly notice_rate_limited: string = '模型配额受限：%s';
  static readonly notice_uploading: string = '⏳';

  static fill(template: string, a: string): string {
    return template.replace('%s', a);
  }

  static fill2(template: string, a: string, b: string): string {
    return template.replace('%s', a).replace('%s', b);
  }

  static fillN(template: string, n: number): string {
    return template.replace('%d', `${n}`);
  }

  static fillN2(template: string, a: string, n: number): string {
    return template.replace('%s', a).replace('%d', `${n}`);
  }

  /** Replace successive '%d' placeholders in order. */
  static fillNums(template: string, values: number[]): string {
    let out = template;
    for (const v of values) {
      out = out.replace('%d', `${v}`);
    }
    return out;
  }

  /**
   * Group header for one command category. The desktop registry owns this
   * vocabulary and grows it — a PawApp reports `pawapp:<id>` — so anything the
   * app doesn't know is headed by its raw name instead of being dropped or
   * folded into a neighbouring group. The router does emit an empty category
   * when a name resolves to no spec, and a blank header would read as a glitch.
   */
  static slashGroup(category: string): string {
    if (category.length === 0) {
      return Copy.slash_group_other;
    }
    switch (category) {
      case 'builtin':
        return Copy.slash_group_builtin;
      case 'conversation':
        return Copy.slash_group_conversation;
      case 'control':
        return Copy.slash_group_control;
      case 'daemon':
        return Copy.slash_group_daemon;
      case 'skill':
        return Copy.slash_group_skill;
      case 'auto':
        return Copy.slash_group_auto;
      case 'user':
        return Copy.slash_group_user;
      case 'mode':
        return Copy.slash_group_mode;
      case 'loop':
      case 'custom_loop':
        return Copy.slash_group_loop;
      case 'plugin':
        return Copy.slash_group_plugin;
      default:
        return category;
    }
  }
}
