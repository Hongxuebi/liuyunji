# 流云记（liuyunji）开发日志

> 与 love-helper 同步开发。版本号与 love-helper 同步映射。

## v0.9.21 ~ v0.9.24 — 锁定模式 + ASR 修复（2026-05-14）

### v0.9.21 — 锁定模式桌面端触发挂断修复
**同步 love-helper v7.2.6**

**问题**：桌面端点击 🔒（锁定模式）按钮触发挂断而非发送语音。鸿蒙端正常。

**根因：输入设备差异**。`#hangupBtn` 有两个独立 `addEventListener`：
1. `_D.hb`（滑动交互层，先注册）— 锁定模式调 `_finishLk()` 发送语音
2. `$('hangupBtn')`（挂断层，后注册）— 始终执行挂断

- **鸿蒙（触摸屏）**：touchend 的 `preventDefault()` 阻止浏览器合成 click → 第二个监听器不触发 ✅
- **桌面（鼠标）**：浏览器合成 click → 第二个监听器触发 → 挂断 ❌

**修复**：`_D.hb` 加 `mousedown` 监听器，逻辑与 touchend 一致（`e.preventDefault()` + `_finishLk()`）。

### v0.9.22 — sendToWebView 原生回调被吞修复

**问题**：锁定模式点击🔒没有发送语音。ASR/TTS 所有原生回调静默消失。

**根因**：`sendToWebView()` 走 `__nativeBridge__._onNativeEvent` 路由，但：
1. API 网关 `methodList` 没注册 `_onNativeEvent` → `b._onNativeEvent` 不存在
2. JS 端也没定义 `window._nativeEventHandler`
3. handler 始终 null → `if(handler)` 为 false → **什么都不执行**

**修复**：改为和 doubaodadianhua 一致——直接调 `window.handleNativeEvent()`。

### v0.9.24 — ASR 第二次录音失败修复

**问题**：第一次长按 mic 录音→松手→正常发送。一轮对话后，再长按 mic 松手，看不到"发送了东西"。

**根因链（两处缺失）**：

| 缺失 | 后果 |
|------|------|
| `startAsr()` 未设 `this.isListening = true` | `stopAsr()` 检查 `!isListening` → 直接返回 → `stopAsrCapture()` 不执行 → `isCapturing` 保持 true → 第二次 `startAsrCapture()` 在 `if(isCapturing) return` 处直接跳过 |
| `startAsr()` 未重置 `this.isStopping = false` | 第一次松手后 `isStopping = true`，第二次 `readDataHandler` → `if(!isStopping && ...)` 丢弃所有音频 → ASR 引擎收不到数据 → 永不触发 `onResult` |

**修复**：在 `startAsr()` 入口加：
```typescript
this.isListening = true;
this.isStopping = false;
```

**参考**：doubaodadianhua `Index.ets` 第258-259行。状态机完整生命周期必须有 reset 环节。

## 版本列表

### v0.9.16 — 通话对话重复修复（2026-05-13）
- **同步 love-helper v7.2.2**
- 根因：`finishTtsUI` 的 `addChat('ai', lastAiText)` 与对话管理.js 的 `添加通话对话` 重复
- 修复：通话浮层显示时 `finishTtsUI` 跳过 `addChat`

### v0.9.14 ~ v0.9.15 — 通话 UI 布局修复（2026-05-13）
- **同步 love-helper v7.2.0 ~ v7.2.1**
- v0.9.14: caption-area position:absolute 权重覆盖修复
- v0.9.15: 气泡 CSS 变量化 + 通话记录 flex 滚动修复

### v0.9.2 — 删除通话验证浮层（2026-05-13）
- 删除通话验证浮层 CSS + DOM，引用处只改 3 行 guard 判断

### v0.8.7 ~ v0.8.9 — 豆包融合 Phase 1-3（2026-05-13）
- Phase 0 (v0.8.0): Haru Live2D 模型加载验证
- Phase 1 (v0.8.1~v0.8.6): 核心通话浮层 UI 融合 + 8 个关键 Bug 修复
- Phase 2 (v0.8.7): 7 角色完整迁移（Haru/Hiyori/Mark/Natori/Mao/Gothic/Rattan）
- Phase 3 (v0.8.8~v0.8.9): 代码审计修复（settingsBtn/hangupBtn 函数缺失）

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
- ASR 引擎生命周期管理（isListening/isStopping/isCapturing）须与 doubaodadianhua 保持同步

## v0.9.27 — 2026-05-14
### 智能体编辑面板 TTS 语音参数（同步 love-helper v7.2.9）
- 智能体编辑面板.js + 智能体编辑面板-样式.css: 同步 TTS 音调/语速滑块
- index.html: aiSpeak 优先从智能体配置读 ttsPitch/ttsSpeed
