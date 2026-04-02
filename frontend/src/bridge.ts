/**
 * Swift ↔ WebView 通信桥接层
 * JS → Swift: window.webkit.messageHandlers.bridge.postMessage()
 * Swift → JS: webView.evaluateJavaScript() 调用 window.nativeBridge.*
 */

export type NativeMessage = {
  type: string;
  payload?: any;
};

type MessageHandler = (payload: any) => void;

class Bridge {
  private handlers: Map<string, MessageHandler[]> = new Map();

  constructor() {
    // Swift 通过 evaluateJavaScript 调用此方法向 JS 发送消息
    (window as any).nativeBridge = {
      receive: (type: string, payload: any) => {
        this.emit(type, payload);
      },
    };
  }

  /** 向 Swift 发送消息 */
  send(type: string, payload?: any): void {
    const msg: NativeMessage = { type, payload };
    try {
      (window as any).webkit?.messageHandlers?.bridge?.postMessage(msg);
    } catch {
      // 开发模式下无 webkit，打印到控制台
      console.log('[Bridge → Swift]', msg);
    }
  }

  /** 监听来自 Swift 的消息 */
  on(type: string, handler: MessageHandler): () => void {
    if (!this.handlers.has(type)) {
      this.handlers.set(type, []);
    }
    this.handlers.get(type)!.push(handler);
    return () => {
      const list = this.handlers.get(type);
      if (list) {
        const idx = list.indexOf(handler);
        if (idx >= 0) list.splice(idx, 1);
      }
    };
  }

  private emit(type: string, payload: any): void {
    const list = this.handlers.get(type);
    if (list) {
      list.forEach((h) => h(payload));
    }
  }
}

export const bridge = new Bridge();
