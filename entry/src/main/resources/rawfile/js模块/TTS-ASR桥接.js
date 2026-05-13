// TTS-ASR桥接.js — JS 端原生桥接模块
// 
// 职责：
//   1. 接收 Index.ets 通过 sendToWebView 发来的原生事件
//   2. 向上层模块（通话管理.js、角色管理.js）暴露 TTS/ASR API
//   3. 管理事件监听器注册/注销
//
// 依赖：__nativeBridge__ 已由 Index.ets 通过 javaScriptProxy 注入

(function() {
  'use strict';

  // ========== 事件监听器管理 ==========
  const _listeners = {};

  /**
   * 注册事件监听器
   * @param {string} event - 事件名: ttsStart/ttsComplete/ttsStop/ttsError/ttsData/asrStart/asrResult/asrComplete/asrError/audioLevel
   * @param {Function} fn - 回调函数
   */
  function on(event, fn) {
    if (!_listeners[event]) _listeners[event] = [];
    _listeners[event].push(fn);
  }

  /**
   * 注销事件监听器
   */
  function off(event, fn) {
    const list = _listeners[event];
    if (!list) return;
    const idx = list.indexOf(fn);
    if (idx >= 0) list.splice(idx, 1);
  }

  /**
   * 触发事件
   */
  function _emit(event, data) {
    const list = _listeners[event];
    if (!list) return;
    for (let i = 0; i < list.length; i++) {
      try { list[i](data); } catch(e) {
        console.error('[TTS-ASR桥接] 事件处理异常:', event, e);
      }
    }
  }

  // ========== 原生事件接收（Index.ets 调用） ==========
  // Index.ets 的 sendToWebView 会调用 __nativeBridge__._onNativeEvent(msg, data)

  const bridge = window.__nativeBridge__ || window.nativeBridge;
  if (bridge) {
    bridge._onNativeEvent = function(msg, data) {
      switch (msg) {
        case 'onTtsStart':
          _emit('ttsStart', {});
          break;
        case 'onTtsComplete':
          _emit('ttsComplete', {});
          break;
        case 'onTtsStop':
          _emit('ttsStop', {});
          break;
        case 'onTtsError':
          _emit('ttsError', { message: data });
          break;
        case 'onTtsData':
          // data = 电平值字符串 (0.000~1.000)
          _emit('ttsData', { level: parseFloat(data) || 0 });
          break;
        case 'onAsrStart':
          _emit('asrStart', {});
          break;
        case 'onAsrResult':
          _emit('asrResult', { text: data });
          break;
        case 'onAsrComplete':
          _emit('asrComplete', {});
          break;
        case 'onAsrError':
          _emit('asrError', { message: data });
          break;
        case 'onAudioLevel':
          _emit('audioLevel', { size: parseInt(data) || 0 });
          break;
        default:
          console.log('[TTS-ASR桥接] 未知原生事件:', msg, data);
      }
    };
  }

  // ========== 公共 API ==========

  /**
   * TTS 朗读文本
   * @param {string} text - 要朗读的文本
   * @param {number} [pitch=1.0] - 音高 (0.5~2.0)
   * @param {number} [speed=1.0] - 语速 (0.5~2.0)
   */
  function speak(text, pitch, speed) {
    const b = window.__nativeBridge__ || window.nativeBridge;
    if (!b || typeof b.ttsSpeak !== 'function') {
      console.warn('[TTS-ASR桥接] ttsSpeak 不可用');
      return;
    }
    b.ttsSpeak(text || '', pitch, speed);
  }

  /**
   * 停止 TTS 朗读
   */
  function stopSpeak() {
    const b = window.__nativeBridge__ || window.nativeBridge;
    if (!b || typeof b.ttsStop !== 'function') return;
    b.ttsStop();
  }

  /**
   * 开始 ASR 语音识别
   */
  function startListening() {
    const b = window.__nativeBridge__ || window.nativeBridge;
    if (!b || typeof b.startAsr !== 'function') {
      console.warn('[TTS-ASR桥接] startAsr 不可用');
      return;
    }
    b.startAsr();
  }

  /**
   * 停止 ASR 语音识别
   */
  function stopListening() {
    const b = window.__nativeBridge__ || window.nativeBridge;
    if (!b || typeof b.stopAsr !== 'function') return;
    b.stopAsr();
  }

  /**
   * 检查 TTS 是否可用（仅检查 bridge 方法存在，不检查引擎就绪状态）
   */
  function isTtsAvailable() {
    const b = window.__nativeBridge__ || window.nativeBridge;
    return !!(b && typeof b.ttsSpeak === 'function');
  }

  /**
   * 检查 ASR 是否可用
   */
  function isAsrAvailable() {
    const b = window.__nativeBridge__ || window.nativeBridge;
    return !!(b && typeof b.startAsr === 'function');
  }

  // ========== 暴露到 window ==========
  window.TTS_ASR桥接 = {
    on: on,
    off: off,
    speak: speak,
    stopSpeak: stopSpeak,
    startListening: startListening,
    stopListening: stopListening,
    isTtsAvailable: isTtsAvailable,
    isAsrAvailable: isAsrAvailable
  };

  console.log('[TTS-ASR桥接] 模块初始化完成', {
    ttsAvailable: isTtsAvailable(),
    asrAvailable: isAsrAvailable()
  });

})();
