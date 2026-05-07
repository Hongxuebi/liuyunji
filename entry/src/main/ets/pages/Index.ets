import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = '流云记';
const DOMAIN = 0xFF00;

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
        // 禁用 Web 组件自带的侧滑前进/后退手势，防止吃掉系统返回手势
        .gestureBackForward(false)
        .javaScriptProxy({
          object: this.bridge,
          name: 'nativeBridge',
          methodList: ['exitApp'],
          controller: this.controller,
        })
        // Web 组件级的返回拦截（比页面级更早触发）
        .onBackPress(() => {
          hilog.info(DOMAIN, TAG, 'Web.onBackPress triggered');
          try {
            this.controller.runJavaScript('window._handleBack?.()');
          } catch (e) {
            hilog.error(DOMAIN, TAG, 'Web.onBackPress runJavaScript failed: %{public}s', JSON.stringify(e));
          }
          return true;
        })
    }
    .width('100%')
    .height('100%')
  }

  // 页面级返回键 / 手势边缘返回（兜底）
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
