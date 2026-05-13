import { webview } from '@kit.ArkWeb';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { picker, fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { textToSpeech, speechRecognizer } from '@kit.CoreSpeechKit';
import { abilityAccessCtrl, PermissionRequestResult } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import audio from '@ohos.multimedia.audio';
import { resourceManager } from '@kit.LocalizationKit';

interface MsgEntry {
  content: string;
  role: string;
}

interface ResourceFilter {
  type: string;
  top_k: number;
}

interface SearchBody {
  messages: MsgEntry[];
  search_source: string;
  resource_type_filter: ResourceFilter[];
}

interface RequestConfig {
  method: http.RequestMethod;
  header: Record<string, string>;
  extraData: string;
  connectTimeout: number;
  readTimeout: number;
  expectDataType: http.HttpDataType;
  usingCache: boolean;
}

const TAG = '流云记';
const DOMAIN = 0xFF00;

function safeErrorMessage(e: Object): string {
  if (e instanceof Error) {
    return e.message;
  }
  try {
    const msg = (e as Record<string, Object>)['message'];
    if (msg !== undefined) {
      return String(msg);
    }
  } catch (ee) {
    // ignore
  }
  return String(e);
}

function _safeEscapeJson(s: string): string {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (ch === '"') {
      out += '\\"';
    } else if (ch === '\\') {
      out += '\\\\';
    } else if (ch === '\n') {
      out += '\\n';
    } else if (ch === '\r') {
      out += '\\r';
    } else if (ch === '\t') {
      out += '\\t';
    } else {
      out += ch;
    }
  }
  return out;
}

// NativeBridge — 流云记原有功能（saveFile/saveTextFile/baiduSearch/exitApp）
// TTS/ASR 方法直接在 javaScriptProxy 上用内联对象（同豆宝模式）
class NativeBridge {
  private context: common.UIAbilityContext | null = null;

  setContext(ctx: common.UIAbilityContext): void {
    this.context = ctx;
  }

  exitApp(): void {
    if (!this.context) return;
    try {
      this.context.terminateSelf();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'exitApp failed: %{public}s', JSON.stringify(e));
    }
  }

  async saveFile(filename: string, base64Data: string): Promise<string> {
    try {
      const pureBase64 = base64Data.includes(',') ? base64Data.split(',')[1] : base64Data;
      const savePicker = new picker.DocumentViewPicker(this.context!);
      const uri = await savePicker.save({ newFileNames: [filename] });
      if (uri.length === 0) {
        return JSON.stringify({ success: false, error: '用户取消保存' });
      }
      const base64Helper = new util.Base64Helper();
      const buffer = base64Helper.decodeSync(pureBase64).buffer as ArrayBuffer;
      const file = fileIo.openSync(uri[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE);
      fileIo.writeSync(file.fd, buffer);
      fileIo.closeSync(file);
      return JSON.stringify({ success: true });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'saveFile failed: %{public}s', JSON.stringify(e));
      return JSON.stringify({ success: false, error: safeErrorMessage(e as Object) });
    }
  }

  async saveTextFile(filename: string, text: string): Promise<string> {
    try {
      const savePicker = new picker.DocumentViewPicker(this.context!);
      const uri = await savePicker.save({ newFileNames: [filename] });
      if (uri.length === 0) {
        return JSON.stringify({ success: false, error: '用户取消保存' });
      }
      const encoder = new util.TextEncoder();
      const buffer = encoder.encode(text);
      const file = fileIo.openSync(uri[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE);
      fileIo.writeSync(file.fd, buffer.buffer as ArrayBuffer);
      fileIo.closeSync(file);
      return JSON.stringify({ success: true });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'saveTextFile failed: %{public}s', JSON.stringify(e));
      return JSON.stringify({ success: false, error: safeErrorMessage(e as Object) });
    }
  }

  async baiduSearch(keyword: string, apiKey: string): Promise<string> {
    const httpRequest = http.createHttp();
    try {
      const url: string = 'https://qianfan.baidubce.com/v2/ai_search/web_search';
      const msgEntry: MsgEntry = { content: keyword, role: 'user' };
      const filter: ResourceFilter = { type: 'web', top_k: 5 };
      const searchBody: SearchBody = {
        messages: [msgEntry],
        search_source: 'baidu_search_v2',
        resource_type_filter: [filter]
      };
      const body: string = JSON.stringify(searchBody);
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + apiKey
      };
      const config: RequestConfig = {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: body,
        connectTimeout: 15000,
        readTimeout: 15000,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false
      };
      const result: http.HttpResponse = await httpRequest.request(url, config);
      if (result.responseCode === 200) {
        return result.result as string;
      } else {
        const errorText: string = result.result as string;
        return '{"success":false,"error":"HTTP ' + result.responseCode.toString() + ': ' + _safeEscapeJson(errorText.slice(0, 200)) + '"}';
      }
    } catch (e) {
      const errMsg: string = JSON.stringify(e);
      return '{"success":false,"error":"' + _safeEscapeJson(errMsg) + '"}';
    } finally {
      httpRequest.destroy();
    }
  }
}

@Entry
@Component
struct Index {
  controller: webview.WebviewController = new webview.WebviewController();
  private bridge: NativeBridge = new NativeBridge();

  // ====== TTS 引擎 ======
  private ttsEngine: textToSpeech.TextToSpeechEngine | null = null;
  private ttsReady: boolean = false;

  // ====== ASR 引擎 ======
  private asrEngine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private asrInitDone: boolean = false;
  private isListening: boolean = false;
  private isCapturing: boolean = false;
  private isStopping: boolean = false;
  private asrSessionId: string = '';
  private audioCapturer: audio.AudioCapturer | null = null;
  private readDataHandler: ((buf: ArrayBuffer) => void) | null = null;
  private lastMouthTime: number = 0;

  // ====== 沙箱路径 ======
  private destDir: string = '';
  @State webUrl: string = '';

  aboutToAppear(): void {
    let ctx = getContext(this) as common.UIAbilityContext;
    let filesDir: string = ctx.filesDir;

    this.bridge.setContext(ctx);

    // 复制全部 web 资源 + Live2D 文件到沙箱，使用 file:// 加载
    this.destDir = filesDir + '/live2d';
    this.copyRawFiles(ctx, this.destDir);
    this.webUrl = 'file://' + this.destDir + '/index.html';
    console.info('======== Target URL: ' + this.webUrl);

    // 请求麦克风权限
    this.requestMicrophonePermission(ctx);

    // 预热 TTS 引擎
    this.initTtsEngine();
    // 预热 ASR 引擎
    this.initAsrEngine();

    hilog.info(DOMAIN, TAG, 'aboutToAppear done');
  }

  aboutToDisappear(): void {
    this.destroyTtsEngine();
    this.stopAsr();
    hilog.info(DOMAIN, TAG, 'aboutToDisappear');
  }

  // ============================================================
  //  麦克风权限
  // ============================================================

  private async requestMicrophonePermission(ctx: common.UIAbilityContext): Promise<void> {
    const atManager = abilityAccessCtrl.createAtManager();
    try {
      atManager.requestPermissionsFromUser(ctx, ['ohos.permission.MICROPHONE'])
        .then((result: PermissionRequestResult) => {
          hilog.info(DOMAIN, TAG, 'microphone permission: %{public}d', result.authResults[0]);
        });
    } catch (e) {
      console.error('======== mic permission failed: ' + JSON.stringify(e));
    }
  }

  // ============================================================
  //  TTS 引擎（从豆宝搬入，person=13 聆小珊）
  // ============================================================

  private async initTtsEngine(): Promise<void> {
    try {
      console.info('======== TTS: creating engine');
      const engine: textToSpeech.TextToSpeechEngine = await textToSpeech.createEngine({
        language: 'zh-CN',
        online: 1,
        person: 13
      });
      this.ttsEngine = engine;
      engine.setListener({
        onStart: () => {
          console.info('======== TTS: onStart');
          this.sendToWebView('onTtsStart', '');
        },
        onComplete: () => {
          console.info('======== TTS: onComplete');
          this.sendToWebView('onTtsComplete', '');
        },
        onError: (_requestId: string, _errorCode: number, errorMessage: string) => {
          console.error('======== TTS error: ' + errorMessage);
          this.sendToWebView('onTtsError', errorMessage);
        },
        onStop: () => {
          console.info('======== TTS: onStop');
          this.sendToWebView('onTtsStop', '');
        },
        onData: (requestId: string, audioData: ArrayBuffer): void => {
          const now = Date.now();
          if (now - this.lastMouthTime < 16) return;
          this.lastMouthTime = now;
          try {
            const view = new Int16Array(audioData);
            let sum = 0;
            for (let i = 0; i < view.length; i++) {
              const v = view[i] / 32768;
              sum += v * v;
            }
            const rms = Math.sqrt(sum / view.length);
            const level = rms < 0.02 ? 0.05 : Math.min(1, rms * 3.0 + 0.08);
            this.sendToWebView('onTtsData', level.toFixed(3));
          } catch (_e) {}
        }
      });
      await new Promise<void>(resolve => setTimeout(resolve, 300));
      this.ttsReady = true;
      console.info('======== TTS engine ready');
    } catch (e) {
      this.ttsReady = false;
      console.error('======== TTS engine failed: ' + JSON.stringify(e));
    }
  }

  private async destroyTtsEngine(): Promise<void> {
    if (!this.ttsEngine) return;
    try {
      await this.ttsEngine.shutdown();
      this.ttsEngine = null;
      this.ttsReady = false;
      console.info('======== TTS shutdown');
    } catch (e) {
      console.error('======== TTS shutdown error: ' + JSON.stringify(e));
    }
  }

  // TTS 朗读（JS Bridge 调用）
  private ttsSpeak(text: string, pitch?: number, speed?: number): void {
    if (!text || text.trim().length === 0) return;
    if (!this.ttsEngine || !this.ttsReady) {
      console.error('======== TTS not ready');
      this.sendToWebView('onTtsError', 'TTS引擎未就绪');
      return;
    }
    try {
      this.ttsEngine.speak(text, {
        requestId: 'tts_' + Date.now().toString(),
        extraParams: {
          speed: speed !== undefined ? speed : 1.0,
          volume: 2,
          pitch: pitch !== undefined ? pitch : 1.0,
          queueMode: 0,
        }
      });
    } catch (e) {
      console.error('======== TTS speak failed: ' + JSON.stringify(e));
    }
  }

  // TTS 停止（JS Bridge 调用，打断式）
  private ttsStop(): void {
    if (!this.ttsEngine) return;
    try {
      this.ttsEngine.speak(' ', {
        requestId: 'tts_interrupt_' + Date.now().toString(),
        extraParams: { queueMode: 0, speed: 10 }
      });
    } catch (_e) {}
    setTimeout(() => {
      try { this.ttsEngine?.stop(); } catch (_e) {}
    }, 80);
  }

  // ============================================================
  //  ASR 引擎（从豆宝搬入）
  // ============================================================

  private initAsrEngine(): void {
    if (this.asrEngine) return;

    const initParams: speechRecognizer.CreateEngineParams = {
      'language': 'zh-CN',
      'online': 1
    };

    speechRecognizer.createEngine(initParams,
      (err: BusinessError | null, engine: speechRecognizer.SpeechRecognitionEngine): void => {
        if (err) {
          console.error('======== ASR engine failed: ' + err.code + ' ' + err.message);
          return;
        }
        this.asrEngine = engine;
        this.asrInitDone = true;

        engine.setListener({
          onStart: (_sessionId: string, _eventMessage: string): void => {
            console.info('======== ASR: onStart');
          },
          onEvent: (_sessionId: string, _eventCode: number, _eventMessage: string): void => {},
          onResult: (_sessionId: string, result: speechRecognizer.SpeechRecognitionResult): void => {
            console.info('======== ASR result: ' + result.result);
            if (result.isFinal) {
              this.sendToWebView('onAsrResult', result.result);
            }
          },
          onComplete: (_sessionId: string): void => {
            console.info('======== ASR: onComplete');
            this.isListening = false;
            this.sendToWebView('onAsrComplete', '');
          },
          onError: (_sessionId: string, errorCode: number, errorMessage: string): void => {
            console.error('======== ASR error: ' + errorCode + ' ' + errorMessage);
            this.isListening = false;
            this.stopAsrCapture();
            this.sendToWebView('onAsrError', '识别错误(' + errorCode + '): ' + errorMessage);
          }
        });

        console.info('======== ASR engine ready');
      });
  }

  // ASR 开始（JS Bridge 调用）
  private startAsr(): void {
    if (!this.asrEngine || !this.asrInitDone) {
      this.sendToWebView('onAsrError', 'ASR引擎未就绪');
      return;
    }
    if (this.isListening) return;

    this.isListening = true;
    this.isStopping = false;
    this.asrSessionId = 'asr_' + Date.now().toString();

    try {
      this.asrEngine.startListening({
        sessionId: this.asrSessionId,
        audioInfo: {
          audioType: 'pcm',
          sampleRate: 16000,
          soundChannel: 1,
          sampleBit: 16
        }
      });
      this.startAsrCapture();
    } catch (e) {
      console.error('======== ASR start failed: ' + JSON.stringify(e));
      this.isListening = false;
      this.sendToWebView('onAsrError', '录音启动失败');
    }
  }

  // ASR 停止（JS Bridge 调用）
  private stopAsr(): void {
    if (!this.isListening) return;
    this.isListening = false;
    this.stopAsrCapture();
  }

  // 音频采集启动
  private async startAsrCapture(): Promise<void> {
    if (this.isCapturing) return;
    try {
      const capturerOpts: audio.AudioCapturerOptions = {
        streamInfo: {
          samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
          channels: audio.AudioChannel.CHANNEL_1,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
        },
        capturerInfo: {
          source: audio.SourceType.SOURCE_TYPE_VOICE_RECOGNITION,
          capturerFlags: 0
        }
      };

      const capturer: audio.AudioCapturer = await audio.createAudioCapturer(capturerOpts);
      this.audioCapturer = capturer;

      const sidRef: string = this.asrSessionId;
      this.readDataHandler = (buf: ArrayBuffer): void => {
        if (!this.isStopping && buf.byteLength > 0) {
          const safeBuf: Uint8Array = new Uint8Array(buf);
          this.asrEngine?.writeAudio(sidRef, safeBuf);
        }
      };
      capturer.on('readData', this.readDataHandler);
      await capturer.start();
      this.isCapturing = true;
      this.sendToWebView('onAsrStart', '');
    } catch (e) {
      console.error('======== ASR capture start failed: ' + JSON.stringify(e));
      this.isListening = false;
      this.stopAsrCapture();
      this.sendToWebView('onAsrError', '录音启动失败');
    }
  }

  // 音频采集停止
  private stopAsrCapture(): void {
    this.isStopping = true;
    this.isCapturing = false;

    setTimeout((): void => {
      try {
        this.asrEngine?.finish(this.asrSessionId);
      } catch (_e) {}
      try {
        if (this.audioCapturer) {
          this.audioCapturer.stop();
          this.audioCapturer.release();
        }
      } catch (_e) {}
      this.audioCapturer = null;
      this.readDataHandler = null;
    }, 300);
  }

  // ============================================================
  //  sendToWebView
  // ============================================================

  private sendToWebView(msg: string, data: string): void {
    try {
      const safeData: string = _safeEscapeJson(data);
      const js: string = `window.handleNativeEvent('${msg}','${safeData}')`;
      this.controller.runJavaScript(js);
    } catch (e) {
      console.error('======== sendToWebView error: ' + JSON.stringify(e));
    }
  }

  // ============================================================
  //  copyRawFiles
  // ============================================================

  private copyRawFiles(ctx: common.UIAbilityContext, destDir: string): void {
    const resMgr: resourceManager.ResourceManager = ctx.resourceManager;

    // ★ 所有 web 资源（切换到 file:// 加载后需全部复制）
    const files: string[] = [
      'index.html',
      'baidu-proxy.js',
      'live2dcubismcore.min.js',
      'l2d.bundle.js',
      'Haru/Haru.model3.json', 'Haru/Haru.moc3', 'Haru/Haru.physics3.json',
      'Haru/Haru.pose3.json', 'Haru/Haru.cdi3.json', 'Haru/Haru.userdata3.json',
      'Haru/Haru.2048/texture_00.png', 'Haru/Haru.2048/texture_01.png',
      'Haru/expressions/F00.exp3.json', 'Haru/expressions/F01.exp3.json',
      'Haru/expressions/F02.exp3.json', 'Haru/expressions/F03.exp3.json',
      'Haru/expressions/F04.exp3.json', 'Haru/expressions/F05.exp3.json',
      'Haru/expressions/F06.exp3.json', 'Haru/expressions/F07.exp3.json',
      'Haru/expressions/F08.exp3.json',
      'Haru/motions/haru_g_idle.motion3.json',
      'Haru/motions/haru_g_m01.motion3.json', 'Haru/motions/haru_g_m02.motion3.json',
      'Haru/motions/haru_g_m03.motion3.json', 'Haru/motions/haru_g_m04.motion3.json',
      'Haru/motions/haru_g_m05.motion3.json', 'Haru/motions/haru_g_m06.motion3.json',
      'Haru/motions/haru_g_m07.motion3.json', 'Haru/motions/haru_g_m08.motion3.json',
      'Haru/motions/haru_g_m09.motion3.json', 'Haru/motions/haru_g_m10.motion3.json',
      'Haru/motions/haru_g_m11.motion3.json', 'Haru/motions/haru_g_m12.motion3.json',
      'Haru/motions/haru_g_m13.motion3.json', 'Haru/motions/haru_g_m14.motion3.json',
      'Haru/motions/haru_g_m15.motion3.json', 'Haru/motions/haru_g_m16.motion3.json',
      'Haru/motions/haru_g_m17.motion3.json', 'Haru/motions/haru_g_m18.motion3.json',
      'Haru/motions/haru_g_m19.motion3.json', 'Haru/motions/haru_g_m20.motion3.json',
      'Haru/motions/haru_g_m21.motion3.json', 'Haru/motions/haru_g_m22.motion3.json',
      'Haru/motions/haru_g_m23.motion3.json', 'Haru/motions/haru_g_m24.motion3.json',
      'Haru/motions/haru_g_m25.motion3.json', 'Haru/motions/haru_g_m26.motion3.json',
      'Mark/Mark.model3.json', 'Mark/Mark.moc3', 'Mark/Mark.physics3.json',
      'Mark/Mark.cdi3.json', 'Mark/Mark.userdata3.json',
      'Mark/Mark.2048/texture_00.png',
      'Mark/expressions/F01.exp3.json', 'Mark/expressions/F02.exp3.json',
      'Mark/motions/mark_m01.motion3.json', 'Mark/motions/mark_m02.motion3.json',
      'Mark/motions/mark_m03.motion3.json', 'Mark/motions/mark_m04.motion3.json',
      'Mark/motions/mark_m05.motion3.json', 'Mark/motions/mark_m06.motion3.json',
      // === Hiyori ===
      'Hiyori/Hiyori.model3.json', 'Hiyori/Hiyori.moc3', 'Hiyori/Hiyori.cdi3.json',
      'Hiyori/Hiyori.physics3.json', 'Hiyori/Hiyori.pose3.json', 'Hiyori/Hiyori.userdata3.json',
      'Hiyori/Hiyori.2048/texture_00.png', 'Hiyori/Hiyori.2048/texture_01.png',
      'Hiyori/expressions/F01.exp3.json', 'Hiyori/expressions/F02.exp3.json',
      'Hiyori/motions/Hiyori_m01.motion3.json', 'Hiyori/motions/Hiyori_m02.motion3.json',
      'Hiyori/motions/Hiyori_m03.motion3.json', 'Hiyori/motions/Hiyori_m05.motion3.json',
      'Hiyori/motions/Hiyori_m06.motion3.json',
      // === Mao ===
      'Mao/Mao.model3.json', 'Mao/Mao.moc3', 'Mao/Mao.cdi3.json',
      'Mao/Mao.physics3.json', 'Mao/Mao.pose3.json',
      'Mao/Mao.2048/texture_00.png',
      'Mao/expressions/exp_01.exp3.json', 'Mao/expressions/exp_02.exp3.json',
      'Mao/expressions/exp_03.exp3.json', 'Mao/expressions/exp_04.exp3.json',
      'Mao/expressions/exp_05.exp3.json', 'Mao/expressions/exp_06.exp3.json',
      'Mao/expressions/exp_07.exp3.json', 'Mao/expressions/exp_08.exp3.json',
      'Mao/motions/mtn_01.motion3.json', 'Mao/motions/mtn_02.motion3.json',
      'Mao/motions/mtn_03.motion3.json', 'Mao/motions/mtn_04.motion3.json',
      'Mao/motions/sample_01.motion3.json', 'Mao/motions/special_01.motion3.json',
      'Mao/motions/special_02.motion3.json', 'Mao/motions/special_03.motion3.json',
      // === Natori ===
      'Natori/Natori.model3.json', 'Natori/Natori.moc3', 'Natori/Natori.cdi3.json',
      'Natori/Natori.physics3.json', 'Natori/Natori.pose3.json',
      'Natori/Natori.2048/texture_00.png',
      'Natori/exp/Angry.exp3.json', 'Natori/exp/Blushing.exp3.json',
      'Natori/exp/Normal.exp3.json', 'Natori/exp/Sad.exp3.json',
      'Natori/exp/Smile.exp3.json', 'Natori/exp/Surprised.exp3.json',
      'Natori/exp/exp_01.exp3.json', 'Natori/exp/exp_02.exp3.json',
      'Natori/exp/exp_03.exp3.json', 'Natori/exp/exp_04.exp3.json',
      'Natori/exp/exp_05.exp3.json',
      'Natori/motions/mtn_00.motion3.json', 'Natori/motions/mtn_01.motion3.json',
      'Natori/motions/mtn_02.motion3.json', 'Natori/motions/mtn_03.motion3.json',
      'Natori/motions/mtn_04.motion3.json', 'Natori/motions/mtn_05.motion3.json',
      'Natori/motions/mtn_06.motion3.json', 'Natori/motions/mtn_07.motion3.json',
      // === 哥特少女 ===
      'characters/ゴシック少女/model03/model03.model3.json',
      'characters/ゴシック少女/model03/model03.moc3',
      'characters/ゴシック少女/model03/model03.cdi3.json',
      'characters/ゴシック少女/model03/model03.physics3.json',
      'characters/ゴシック少女/model03/model03.8192/texture_00.png',
      'characters/ゴシック少女/model03/model03.8192/texture_01.png',
      'characters/ゴシック少女/model03/model03.8192/texture_02.png',
      'characters/ゴシック少女/model03/model03.8192/texture_03.png',
      'characters/ゴシック少女/model03/model03.8192/texture_04.png',
      'characters/ゴシック少女/model03/cheek.exp3.json',
      'characters/ゴシック少女/model03/cheek.motion3.json',
      'characters/ゴシック少女/model03/earringoff.exp3.json',
      'characters/ゴシック少女/model03/earringoff.motion3.json',
      'characters/ゴシック少女/model03/fronthairB.exp3.json',
      'characters/ゴシック少女/model03/fronthairB.motion3.json',
      'characters/ゴシック少女/model03/guruguru.exp3.json',
      'characters/ゴシック少女/model03/guruguru.motion3.json',
      'characters/ゴシック少女/model03/hairpinoff.exp3.json',
      'characters/ゴシック少女/model03/hairpinoff.motion3.json',
      'characters/ゴシック少女/model03/headdressB.exp3.json',
      'characters/ゴシック少女/model03/headdressB.motion3.json',
      'characters/ゴシック少女/model03/headdressW.exp3.json',
      'characters/ゴシック少女/model03/headdressW.motion3.json',
      'characters/ゴシック少女/model03/heart.exp3.json',
      'characters/ゴシック少女/model03/heart.motion3.json',
      'characters/ゴシック少女/model03/highlightoff.exp3.json',
      'characters/ゴシック少女/model03/highlightoff.motion3.json',
      'characters/ゴシック少女/model03/ico_model03.png',
      'characters/ゴシック少女/model03/jitome.exp3.json',
      'characters/ゴシック少女/model03/jitome.motion3.json',
      'characters/ゴシック少女/model03/kirakira .exp3.json',
      'characters/ゴシック少女/model03/kirakira .motion3.json',
      'characters/ゴシック少女/model03/ribbonB.exp3.json',
      'characters/ゴシック少女/model03/ribbonB.motion3.json',
      'characters/ゴシック少女/model03/shock.exp3.json',
      'characters/ゴシック少女/model03/shock.motion3.json',
      'characters/ゴシック少女/model03/shorthair.exp3.json',
      'characters/ゴシック少女/model03/shorthair.motion3.json',
      'characters/ゴシック少女/model03/twintail.exp3.json',
      'characters/ゴシック少女/model03/twintail.motion3.json',
      // === Rattan(白藤) ===
      'Rattan/Rattan.cdi3.json', 'Rattan/Rattan.moc3',
      'Rattan/Rattan.model3.json', 'Rattan/Rattan.physics3.json',
      'Rattan/idle_body.motion3.json', 'Rattan/activity.motion3.json',
      'Rattan/nonono.motion3.json', 'Rattan/nodnod.motion3.json',
      'Rattan/bow.motion3.json', 'Rattan/sigh.motion3.json',
      'Rattan/shrug.motion3.json', 'Rattan/wave.motion3.json',
      'Rattan/tilt.motion3.json', 'Rattan/surprise.motion3.json',
      'Rattan/leanfwd.motion3.json', 'Rattan/leanbak.motion3.json',
      'Rattan/sway.motion3.json',
      'Rattan/Rattan.4096/texture_00.png', 'Rattan/Rattan.4096/texture_01.png',
      'Rattan/Rattan.4096/texture_02.png', 'Rattan/Rattan.4096/texture_03.png',
      'Rattan/Rattan.4096/texture_04.png',
      'Rattan/exp/1.exp3.json', 'Rattan/exp/2.exp3.json',
      'Rattan/exp/3.exp3.json', 'Rattan/exp/4.exp3.json',
      'Rattan/exp/5.exp3.json', 'Rattan/exp/6.exp3.json',
      'Rattan/exp/7.exp3.json', 'Rattan/exp/8.exp3.json',
      'Rattan/exp/9.exp3.json', 'Rattan/exp/10.exp3.json',
      'Rattan/exp/11.exp3.json', 'Rattan/exp/12.exp3.json',
      'Rattan/exp/13.exp3.json', 'Rattan/exp/14.exp3.json',
      'Rattan/exp/15.exp3.json', 'Rattan/exp/16.exp3.json',
      'Rattan/exp/17.exp3.json', 'Rattan/exp/18.exp3.json',
      'Rattan/exp/19.exp3.json', 'Rattan/exp/20.exp3.json',
      'Rattan/exp/loli.exp3.json', 'Rattan/exp/custom.exp3.json',
      // === web 前端资源 ===
      'css/样式.css', 'css/智能体编辑面板-样式.css',
      'js模块/存储适配器.js', 'js模块/调试日志.js',
      'js模块/智能体管理.js', 'js模块/AI记忆管理器.js',
      'js模块/记忆压缩.js', 'js模块/智能提取.js',
      'js模块/生成周报.js', 'js模块/数据备份.js',
      'js模块/API调用.js', 'js模块/对话管理.js',
      'js模块/备忘录管理器.js', 'js模块/备忘录数据.js', 'js模块/备忘录接口.js',
      'js模块/备忘录UI.js', 'js模块/备忘录渲染.js', 'js模块/备忘录事件.js',
      'js模块/设置管理.js', 'js模块/设置浮层.js',
      'js模块/全局函数.js', 'js模块/初始化.js',
      'js模块/智能体选择器.js', 'js模块/标签页.js',
      'js模块/抽屉.js', 'js模块/抽屉底部.js',
      'js模块/对话面板.js', 'js模块/文件上传.js',
      'js模块/更多菜单.js', 'js模块/卡片滑动.js',
      'js模块/智能体编辑面板.js', 'js模块/记忆库面板.js',
      'js模块/智能体权限向导.js', 'js模块/多选状态管理器.js',
      'js模块/导出功能.js', 'js模块/jszip.min.js',
      'js模块/ai-logger.js',
      'js模块/TTS-ASR桥接.js', 'js模块/通话管理.js',
      'js模块/角色管理.js',
    ];

    try {
      let parts: string[] = destDir.split('/');
      let current: string = '';
      for (let i = 0; i < parts.length; i++) {
        if (parts[i].length === 0) continue;
        current = current + '/' + parts[i];
        if (current === ctx.filesDir) continue;
        try { fileIo.mkdirSync(current); } catch (_) {}
      }

      let subDirs: string[] = [
        'css', 'js模块',
        'Haru', 'Haru/Haru.2048', 'Haru/expressions', 'Haru/motions',
        'Hiyori', 'Hiyori/Hiyori.2048', 'Hiyori/expressions', 'Hiyori/motions',
        'Mark', 'Mark/Mark.2048', 'Mark/expressions', 'Mark/motions',
        'Mao', 'Mao/Mao.2048', 'Mao/expressions', 'Mao/motions',
        'Natori', 'Natori/Natori.2048', 'Natori/exp', 'Natori/motions',
        'characters', 'characters/ゴシック少女', 'characters/ゴシック少女/model03', 'characters/ゴシック少女/model03/model03.8192',
        'Rattan', 'Rattan/Rattan.4096', 'Rattan/exp',
      ];
      for (let sd of subDirs) {
        try { fileIo.mkdirSync(destDir + '/' + sd); } catch (_) {}
      }

      for (let i = 0; i < files.length; i++) {
        let f: string = files[i];
        let destPath: string = destDir + '/' + f;
        try {
          try { fileIo.unlinkSync(destPath); } catch (_) {}
          let rawResult = resMgr.getRawFileContentSync(f);
          let data = new Uint8Array(rawResult);
          let file = fileIo.openSync(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
          fileIo.writeSync(file.fd, data.buffer, { offset: data.byteOffset, length: data.byteLength });
          fileIo.closeSync(file);
          console.info('======== Copied: ' + f + ' (' + data.byteLength + ' bytes)');
        } catch (e2) {
          console.error('======== Failed to copy: ' + f + ' error: ' + JSON.stringify(e2));
        }
      }
      console.info('======== Live2D files copied OK');
    } catch (e) {
      console.error('======== copyRawFiles error: ' + JSON.stringify(e));
    }
  }

  // ============================================================
  //  build
  // ============================================================

  build() {
    Column() {
      if (this.webUrl.length > 0) {
        Web({ src: this.webUrl, controller: this.controller })
        .width('100%')
        .height('100%')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .onlineImageAccess(true)
        .mixedMode(MixedMode.All)
        .backgroundColor('#0A0E1A')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .onControllerAttached(() => {
          // 允许 WebView 访问沙箱目录中的文件（file:// 协议）
          try {
            webview.WebviewController.setWebDebuggingAccess(true);
            console.info('======== WebDebuggingAccess enabled');
          } catch (e) {
            console.error('======== setWebDebuggingAccess failed: ' + JSON.stringify(e));
          }
          try {
            this.controller.setPathAllowingUniversalAccess([this.destDir]);
            console.info('======== setPathAllowingUniversalAccess: ' + this.destDir);
          } catch (e) {
            console.error('======== setPathAllowingUniversalAccess failed: ' + JSON.stringify(e));
          }
        })
        .javaScriptProxy({
          object: {
            exitApp: (): void => { this.bridge.exitApp(); },
            saveFile: (filename: string, base64Data: string): Promise<string> => { return this.bridge.saveFile(filename, base64Data); },
            saveTextFile: (filename: string, text: string): Promise<string> => { return this.bridge.saveTextFile(filename, text); },
            baiduSearch: (keyword: string, apiKey: string): Promise<string> => { return this.bridge.baiduSearch(keyword, apiKey); },
            ttsSpeak: (text: string, pitch?: number, speed?: number): void => { this.ttsSpeak(text, pitch, speed); },
            ttsStop: (): void => { this.ttsStop(); },
            startAsr: (): void => { this.startAsr(); },
            stopAsr: (): void => { this.stopAsr(); },
          },
          name: '__nativeBridge__',
          methodList: ['exitApp', 'saveFile', 'saveTextFile', 'baiduSearch', 'ttsSpeak', 'ttsStop', 'startAsr', 'stopAsr'],
          controller: this.controller,
        })
        .onPageEnd(() => {
          console.info('======== WebView page loaded (file://)');
        })
        .onAlert((event: OnAlertEvent) => {
          promptAction.showToast({ message: event.message, duration: 2000 });
          return true;
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  onBackPress(): boolean {
    hilog.info(DOMAIN, TAG, 'Page.onBackPress triggered');
    try {
      this.controller.runJavaScript('window._handleBack?.()');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Page.onBackPress runJavaScript failed: %{public}s', JSON.stringify(e));
    }
    return true;
  }
}
