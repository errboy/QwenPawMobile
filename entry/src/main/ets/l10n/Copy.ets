/**
 * Every user-visible string in the app, in one place.
 * Templates use %s / %d and are expanded by Copy.fill().
 */

export class Copy {
  static readonly app_name: string = 'QwenPaw Mobile';
  static readonly app_tagline: string = '连接局域网主电脑上的 QwenPaw，共享同一个聊天窗口';
  static readonly theme_system: string = '跟随系统';
  static readonly theme_light: string = '浅色';
  static readonly theme_dark: string = '深色';

  // ---------- sign in ----------
  static readonly server_field: string = '服务器地址';
  static readonly server_placeholder: string = 'http://192.168.1.100:8088';
  static readonly username_field: string = '用户名';
  static readonly username_placeholder: string = '服务器未启用认证时可留空';
  static readonly password_field: string = '密码';
  static readonly password_placeholder: string = '可选';
  static readonly action_connect: string = '连接并登录';
  static readonly action_connecting: string = '登录中…';
  static readonly action_use_saved: string = '使用已保存的登录进入';
  static readonly need_server_address: string = '请输入服务器地址，例如 http://192.168.1.100:8088';
  static readonly connecting: string = '正在连接…';
  static readonly auth_disabled_hint: string = '服务器未启用认证，直接进入';
  static readonly bad_credentials: string = '用户名或密码错误';
  static readonly account_locked: string = '尝试过于频繁，账号暂时锁定';

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
  static readonly login_status_online: string = '在线';
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
  static readonly home_foreground_badge: string = '▶ 前台会话';
  static readonly home_foreground_hint: string = '与电脑端共享同一窗口 · 打开后接着上次聊';
  static readonly home_resume: string = '继续 ›';
  static readonly home_running_chip: string = '⏳ 进行中';
  static readonly home_approvals: string = '🔒 %d 项待审批';
  static readonly home_bg_running: string = '⏳ %d 个会话进行中';
  static readonly home_loading: string = '加载会话列表…';
  static readonly home_empty: string = '暂无会话。在电脑端 Console 发起对话后，这里会同步显示。';
  static readonly home_offline: string = '⚠ 无法连接服务器，列表可能已过期';
  static readonly home_refresh: string = '刷新会话列表';
  static readonly home_group_console: string = '控制台会话';
  static readonly home_group_wechat: string = '微信机器人';
  static readonly home_group_feishu: string = '飞书机器人';
  static readonly home_group_other: string = '其他渠道';
  static readonly home_group_count: string = '%s %s · %d';
  static readonly home_group_running: string = '⏳ %d 进行中';
  static readonly home_group_expand: string = '▾ 展开';
  static readonly home_group_collapse: string = '▴ 收起';
  static readonly home_row_running: string = '进行中';
  static readonly home_theme: string = '主题 · %s';
  static readonly home_row_meta: string = '%s · %s';

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
  static readonly chat_queued_hint: string = '排队中 · 点我撤回';
  static readonly chat_attach_gallery: string = '🖼 相册（图片/视频）';
  static readonly chat_attach_files: string = '📄 手机文件';
  static readonly chat_attach_audio: string = '🎵 音频';
  /** Starts a recording; stopping it is the recording bar's job, not this row's. */
  static readonly chat_attach_record: string = '🎙 录一段语音';
  static readonly chat_recording: string = '录音中 %s';
  static readonly chat_rec_stop: string = '停止录音';
  static readonly chat_rec_cancel: string = '丢弃';
  static readonly notice_voice_denied: string = '没有麦克风权限，无法录音';
  static readonly notice_voice_failed: string = '录音失败：%s';
  static readonly notice_voice_code: string = '录音失败（错误码 %d）';
  static readonly notice_voice_none: string = '没有进行中的录音';
  static readonly notice_voice_empty: string = '录音是空的，没有附上文件';
  static readonly chat_reasoning_label: string = '💭 深度思考';
  static readonly chat_tool_label: string = '🔧 %s';
  static readonly chat_tool_output_suffix: string = ' · 输出';
  static readonly chat_default_tool_name: string = '工具';
  static readonly chat_part_image: string = '[图片]';
  static readonly chat_part_video: string = '[视频]';
  static readonly chat_part_audio: string = '[语音]';
  static readonly chat_part_file: string = '[文件: %s]';
  static readonly chat_attachment_line: string = '📎 %s';
  static readonly chat_image_loading: string = '加载图片…';
  static readonly chat_image_unavailable: string = '图片暂不可用';
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
  static readonly notice_load_failed: string = '重连失败：%s';
  static readonly notice_generation_failed: string = '生成失败：%s';
  static readonly notice_stopped: string = '已停止生成';
  static readonly notice_unknown_error: string = '未知错误';
  static readonly notice_upload_failed: string = '上传失败：%s';
  static readonly notice_upload_no_path: string = '上传响应缺少文件路径';
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
}
