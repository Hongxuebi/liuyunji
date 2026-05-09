# 流云记

鸿蒙原生 AI 私人助理 — WebView 嵌入「爱助手」前端 + 原生桥接增强。

## 当前状态

- **版本**：v0.7.11
- **能力**：AI 多智能体对话（DeepSeek）、联网搜索（百度千帆 + 原生桥接）、备忘录管理、情绪日记、数据备份导出、智能体间设定感知
- **平台**：HarmonyOS API 22 (ArkTS + WebView)
- **代码源头**：[爱助手](https://github.com/Hongxuebi/xiuxian123.github.io)（V6.5，前端 JS/CSS/HTML）
- **流云记 rawfile**：由爱助手对应文件同步而来

## 架构

```
ArkTS 容器层
├── WebView（@kit.ArkWeb）— 加载 rawfile/ 下 35+ JS + 2 CSS + 1 HTML
├── NativeBridge — 原生桥接（saveFile / saveTextFile / baiduSearch / onAlert）
└── 原生权限 / 文件系统 / 网络声明

前端层（rawfile/）
├── AI 对话 — DeepSeek API + 百度千帆联网搜索
├── 智能体系统 — 多智能体切换 / 权限管理 / 设定注入
├── 备忘录 — 创建/编辑/收藏/置顶/重要性
├── 抽屉面板 — 头像/智能体切换/设定
└── 工具集 — 9 个 AI 工具（4 智能体管理 + 5 对话管理）
```

## 版本历史

### v0.7.x — 鸿蒙深度兼容 + 智能体增强

| 版本 | 日期 | 核心改动 |
|------|------|---------|
| v0.7.11 | 05-09 | 桌面端百度搜索 CORS 修复（本地代理优先 + 降级直连）；2.61 用户重要提醒注入 |
| v0.7.10 | 05-09 | 其他智能体设定注入（2.60 段，AI 无条件感知所有智能体核心身份/语气） |
| v0.7.9 | 05-09 | 抽屉头像照片恢复；下拉菜单 CSS+JS 配合修复；对话管理会话 ID 覆盖修复；调试面板清理 |
| v0.7.8 | 05-08 | 智能体设定注入修复（修改核心身份/语气后 AI 即时感知） |
| v0.7.7 | 05-08 | 智能体管理 + 对话管理 9 个 AI 工具；系统提示词完善 |
| v0.7.6 | 05-08 | 导出 JSON 空文件修复（TextEncoder.encode → encode；WRITE_ONLY 补 CREATE flag） |
| v0.7.5 | 05-08 | alert → 全局浮动提示体系（16 个 JS 文件替换，alert 残留清零） |
| v0.7.4 | 05-08 | 使用统计自动注入（搜索/对话/备忘录/主题切换计数） |
| v0.7.3 | 05-08 | 系统运行状态自动注入（AI 每次对话感知当前配置） |
| v0.7.2 | 05-08 | 系统提示词强化：联网搜索规则 + 搜索结果注入语气 |
| v0.7.1 | 05-08 | 操作栏按钮 touchend + preventDefault（绕过鸿蒙 click 合成延迟） |
| v0.7 | 05-08 | prompt/confirm → 原生桥接；async 回调补全；AI 工具描述富文本支持；返回手势修复 |

### v0.4 ~ v0.6 — 手势与返回

| 版本 | 日期 | 核心改动 |
|------|------|---------|
| v0.6 | 05-08 | 返回手势双保险 + 文件夹下拉 CSS 重构 |
| v0.5 | 05-08 | （过渡版本） |
| v0.4 | 05-08 | 返回手势修复 + 文件夹下拉位置 + 标签页 touch-action |

### v0.1 ~ v0.3 — 基础迁移

| 版本 | 日期 | 核心改动 |
|------|------|---------|
| v0.3 | 05-07 | 卡片滑动 v5 重构（8px 方向判定 + 误触保护）；智能体专属文件夹注入；权限默认 none |
| v0.2 | 05-07 | 智能体权限向导；删除确认弹窗；重命名同步文件夹；权限默认 mode:none |
| v0.1 | 05-07 | 35 JS + 2 CSS + 1 HTML 全部迁入 rawfile；WebView 容器；网络权限声明 |

## 鸿蒙适配要点

- **文件保存**：Blob + download 不可靠 → `NativeBridge.saveFile` / `saveTextFile`
- **搜索**：WebView CORS 限制 → `NativeBridge.baiduSearch` 原生桥接 + 桌面端本地代理
- **弹窗**：alert 不显示 → 全局 `_显示提示()` 浮动提示体系
- **触控**：click 合成延迟 → touchend + preventDefault 模式
- **设定注入**：agent.json.plugin + system.md 分层互补，2.60/2.61 段无条件注入

## 开发调试

- 桌面端：双击 `index.html`（file://）或 `http://localhost:3777`（debug-server.js）
- 鸿蒙端：rawfile 改后 rebuild 才生效
- 百度搜索代理：`node baidu-proxy.js`（端口 3778）
- 错误速查：`常见错误对照速查.txt`
- 开发日志：`开发日志.md`

## 路线图

- [ ] 模态浮层滚动穿透修复
- [ ] 抽屉拖拽关闭
- [ ] ~80 处 try 无 catch 补全
- [ ] 140 个 click 监听 touchend 审查
- [ ] 初始化串行 await 链优化
- [ ] debounce / throttle

## 关联项目

- **爱助手**（前端源头）：[Hongxuebi/xiuxian123.github.io](https://github.com/Hongxuebi/xiuxian123.github.io)
- **woderiji**（TTS + ASR 鸿蒙应用）：Edge TTS WebSocket + minimp3 解码
