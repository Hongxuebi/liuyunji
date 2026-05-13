# 流云记（liuyunji）开发日志

> 与 love-helper 同步开发。版本号与 love-helper 同步映射。

## 版本列表

### v0.9.16 — 通话对话重复修复（2026-05-13）
- **同步 love-helper v7.2.2**
- 根因：`finishTtsUI` 的 `addChat('ai', lastAiText)` 与对话管理.js 的 `添加通话对话` 重复
- 修复：`finishTtsUI` 检测到通话浮层显示时跳过 `addChat`
- Git tag: `v0.9.16`

### v0.9.14 ~ v0.9.15 — 通话 UI 布局修复（2026-05-13）
- **同步 love-helper v7.2.0 ~ v7.2.1**
- v0.9.14: caption-area position:absolute 权重覆盖修复（CSS 排除列表加 `:not(.caption-area):not(.chat-toggle-btn)`）
- v0.9.15: 气泡背景 CSS 变量化 + 通话记录 flex 滚动修复
- Git tags: `v0.9.14`, `v0.9.15`

### v0.9.2 — 删除通话验证浮层（2026-05-13）
- 删除通话验证浮层 CSS + DOM，引用处只改 3 行 guard 判断
- **注意**：love-helper 删了整个 IIFE，liuyunji 保留结构仅改引用

### v0.8.7 ~ v0.8.9 — 豆包融合 Phase 1-3（2026-05-13）
- **Phase 0 (v0.8.0)**: Haru Live2D 模型加载验证
- **Phase 1 (v0.8.1~v0.8.6)**: 核心通话浮层 UI 融合 + 8 个关键 Bug 修复
- **Phase 2 (v0.8.7)**: 7 角色完整迁移（Haru/Hiyori/Mark/Natori/Mao/Gothic/Rattan）
- **Phase 3 (v0.8.8~v0.8.9)**: 代码审计修复（settingsBtn/hangupBtn 函数缺失）

## 同步机制

- love-helper 为主开发项目，liuyunji 从 love-helper 同步改动
- 同步时优先保持 rawfile 结构与鸿蒙端兼容性
- 版本对照：love-helper v7.x.x ↔ liuyunji v0.9.x

## 鸿蒙特有差异

- 无桌面 `debug-server.js`（使用鸿蒙 DevEco 调试）
- copyRawFiles 须在 Index.ets 中维护文件列表
- subDirs 须在 Index.ets 中维护子目录列表
- 使用鸿蒙原生 TTS-ASR 桥接（非桌面 SpeechSynthesis 降级）
- 语按钮通过 `sendToWebView` 通信（桌面直接 click 事件）
