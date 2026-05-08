import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { picker, fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

const TAG = '流云记';
const DOMAIN = 0xFF00;

// 安全地从 catch 中提取错误信息
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

// 暴露给 JS 的原生桥接对象
class NativeBridge {
  private context: common.UIAbilityContext | null = null;

  setContext(ctx: common.UIAbilityContext): void {
    this.context = ctx;
  }

  // JS 调用：关闭所有面板后仍无内容可退 → 退出 App
  exitApp(): void {
    if (!this.context) {
      return;
    }
    try {
      const ctx: common.UIAbilityContext = this.context;
      ctx.terminateSelf();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'exitApp failed: %{public}s', JSON.stringify(e));
    }
  }

  // JS 调用：保存 base64 数据到文件（二进制，如图片/ZIP）
  // 返回值: JSON.stringify({success:true}) 或 {success:false,error:"xxx"}
  async saveFile(filename: string, base64Data: string): Promise<string> {
    try {
      const pureBase64 = this._stripDataUrlPrefix(base64Data);
      const savePicker = new picker.DocumentViewPicker(this.context!);
      const uri = await savePicker.save({
        newFileNames: [filename]
      });
      if (uri.length === 0) {
        return JSON.stringify({ success: false, error: '用户取消保存' });
      }
      const file = fileIo.openSync(uri[0], fileIo.OpenMode.WRITE_ONLY);
      const buffer = this._base64ToArrayBuffer(pureBase64);
      fileIo.writeSync(file.fd, buffer);
      fileIo.closeSync(file);
      return JSON.stringify({ success: true });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'saveFile failed: %{public}s', JSON.stringify(e));
      return JSON.stringify({ success: false, error: safeErrorMessage(e as Object) });
    }
  }

  // JS 调用：保存文本字符串到文件（JSON/备份，无需 JS 侧自己编 base64）
  // 返回值同 saveFile
  async saveTextFile(filename: string, text: string): Promise<string> {
    try {
      const savePicker = new picker.DocumentViewPicker(this.context!);
      const uri = await savePicker.save({
        newFileNames: [filename]
      });
      if (uri.length === 0) {
        return JSON.stringify({ success: false, error: '用户取消保存' });
      }
      const encoder = new util.TextEncoder();
      const buffer = encoder.encodeInto(text);
      const file = fileIo.openSync(uri[0], fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(file.fd, buffer);
      fileIo.closeSync(file);
      return JSON.stringify({ success: true });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'saveTextFile failed: %{public}s', JSON.stringify(e));
      return JSON.stringify({ success: false, error: safeErrorMessage(e as Object) });
    }
  }

  /** 去除 DataURL 前缀（data:xxx;base64,） */
  private _stripDataUrlPrefix(data: string): string {
    if (data.includes(',')) {
      return data.split(',')[1];
    }
    return data;
  }

  private _base64ToArrayBuffer(base64: string): ArrayBuffer {
    const base64Helper = new util.Base64Helper();
    return base64Helper.decodeSync(base64).buffer as ArrayBuffer;
  }
}

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: NativeBridge = new NativeBridge();

  aboutToAppear(): void {
    this.bridge.setContext(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  build() {
    Column() {
      Web({ src: $rawfile('index.html'), controller: this.controller })
        .width('100%')
        .height('100%')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .backgroundColor('#0A0E1A')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .javaScriptProxy({
          object: this.bridge,
          name: 'nativeBridge',
          methodList: ['exitApp', 'saveFile', 'saveTextFile'],
          controller: this.controller,
        })

    }
    .width('100%')
    .height('100%')
  }

  // 页面级返回键 / 手势边缘返回（兜底）
  onBackPress(): boolean {
    hilog.info(DOMAIN, TAG, 'Page.onBackPress triggered');
    try {
      const ctrl: webview.WebviewController = this.controller;
      ctrl.runJavaScript('window._handleBack?.()');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Page.onBackPress runJavaScript failed: %{public}s', JSON.stringify(e));
    }
    return true;
  }
}
