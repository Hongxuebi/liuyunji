import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';

// 暴露给 JS 的原生桥接对象
class NativeBridge {
  private context: common.UIAbilityContext | null = null;

  setContext(ctx: common.UIAbilityContext): void {
    this.context = ctx;
  }

  // JS 调用：关闭所有面板后仍无内容可退 → 退出 App
  exitApp(): void {
    if (this.context) {
      this.context.terminateSelf();
    }
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
        .javaScriptProxy({
          object: this.bridge,
          name: 'nativeBridge',
          methodList: ['exitApp'],
          controller: this.controller,
        })
    }
    .width('100%')
    .height('100%')
  }

  // 系统返回键 / 手势边缘返回
  // 始终拦截（return true），让 JS 决定是关面板还是退出 App
  onBackPress(): boolean {
    try {
      this.controller.runJavaScript('window._handleBack?.()');
    } catch (e) {
      // WebView 未就绪时忽略
    }
    return true;
  }
}
