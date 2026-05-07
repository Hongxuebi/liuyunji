# 流云记

鸿蒙原生 AI 私人助理，将网页版「爱助手」嵌入 WebView，后续集成原生 TTS/ASR 实现语音通话式交互。

## 当前状态

- **阶段**：v0.2 — 智能体权限体系 + UI 修复
- **能力**：AI 对话（DeepSeek）、联网搜索（百度千帆）、备忘录管理、多智能体（含权限向导）、情绪日记、数据备份
- **平台**：HarmonyOS（ArkTS + WebView）

## 版本历史

### v0.2 — 智能体权限体系（2026-05-07）

- 新增「智能体权限向导」模块，创建智能体时自动引导设置备忘录权限
- 删除智能体时弹窗确认是否删除关联文件夹
- 智能体重命名时同步重命名同名文件夹
- 权限默认从 `mode:'all'` 改为 `mode:'none'`（安全优先）
- `none` 权限下允许创建备忘录（之前被误拦截）
- 智能体编辑弹窗修复：按钮样式 !important 防覆盖、弹窗高度 90vh、文本域滚动
- navigator.onLine 注入位置移到 `<head>` 最前（更早生效）
- 恢复 font-awesome.min.css 引用
- 卡片滑动改为全 passive + CSS touch-action:pan-y 协作（解决鸿蒙竖滚延迟）

### v0.1 — 爱助手 WebView 迁移版（2026-05-07）

- 35 个 JS 模块 + 2 CSS + 1 HTML 全部迁入 rawfile
- WebView 容器：javaScriptAccess + domStorageAccess
- 网络权限声明、navigator.onLine 修复
- 百度搜索代理改为直连

## 路线

- v0.3 — TTS 语音合成（CoreSpeechKit JSBridge）
- v0.4 — ASR 语音识别（说话转文字）
- v0.5 — 通话式 AI 交互体验
