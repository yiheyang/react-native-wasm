import Foundation
import WebKit

let js: String = """
var wasm = {};
var promise = {};

function instantiate (id, bytes) {
  promise[id] = self.Module({
    instantiateWasm: function (info, successCallback) {
      WebAssembly.instantiate(Uint8Array.from(bytes), info).
        then(function (res) {
          successCallback(res.instance);
          return res;
        });
    }
  }).then(function (res) {
    delete promise[id];
    wasm[id] = res;
    window.webkit.messageHandlers.resolve.postMessage(JSON.stringify(
      { id: id, data: JSON.stringify(Object.keys(res)) }));
  }).catch(function (e) {
    delete promise[id];
    window.webkit.messageHandlers.reject.postMessage(
      JSON.stringify({ id: id, data: e.toString() }));
  });
  return true;
}
"""

struct Promise {
    let resolve: RCTPromiseResolveBlock
    let reject: RCTPromiseRejectBlock
}

struct JsResult: Codable {
    let id: String
    let data: String
}

@objc(Wasm)
class Wasm: NSObject, WKScriptMessageHandler {

    var webView: WKWebView!
    var asyncPool: Dictionary<String, Promise> = [:]

    static func requiresMainQueueSetup() -> Bool {
        return true
    }

    override init() {
        super.init()
        let webCfg: WKWebViewConfiguration = WKWebViewConfiguration()

        let userController: WKUserContentController = WKUserContentController()
        userController.add(self, name: "resolve")
        userController.add(self, name: "reject")
        webCfg.userContentController = userController

        webView = WKWebView(frame: .zero, configuration: webCfg)

        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(js) { (value, error) in
                // NOP
            }
        }
    }

    @objc
    func instantiate(_ modId: NSString, initScriptsStr initScripts: NSString, bytesStr bytes: NSString, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) -> Void {
        asyncPool.updateValue(Promise(resolve: resolve, reject: reject), forKey: modId as String)

        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(initScripts as String) { (value, error) in
                if error != nil {
                    self.asyncPool.removeValue(forKey: modId as String)
                    reject("error", "\(error)", nil)
                }
            }

            self.webView.evaluateJavaScript("""
            instantiate("\(modId)", [\(bytes)]);
            """
            ) { (value, error) in
                if error != nil {
                    self.asyncPool.removeValue(forKey: modId as String)
                    reject("error", "\(error)", nil)
                }
            }
        }
    }

    @objc
    func call(_ modId: NSString, funcName name: NSString, arguments args: NSString, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) -> Void {
        asyncPool.updateValue(Promise(resolve: resolve, reject: reject), forKey: modId as String)
        var result: NSString = ""

        DispatchQueue.main.async {
            self.webView.evaluateJavaScript("""
            JSON.stringify(wasm["\(modId)"].\(name)(...JSON.parse(`\(args)`)));
            """
            ) { (value, error) in
                if error != nil {
                    self.asyncPool.removeValue(forKey: modId as String)
                    reject("error", "\(error)", nil)
                } else {
                  if value == nil {
                      result = ""
                  } else {
                      result = value as! NSString
                  }
                  self.asyncPool.removeValue(forKey: modId as String)
                  resolve(result)
                }
            }
        }
    }

    @objc @discardableResult
    func callSync(_ modId: NSString, funcName name: NSString, arguments args: NSString) -> NSString {
        var result: NSString = ""
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript("""
            JSON.stringify(wasm["\(modId)"].\(name)(...JSON.parse(`\(args)`)));
            """
            ) { (value, error) in
                // TODO handle error
                if value == nil {
                    result = ""
                } else {
                    result = value as! NSString
                }
                semaphore.signal()
            }
        }

        semaphore.wait()
        return result
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "resolve" {
            let json = try! JSONDecoder().decode(JsResult.self, from: (message.body as! String).data(using: .utf8)!)
            guard let promise = asyncPool[json.id] else {
                return
            }
            asyncPool.removeValue(forKey: json.id)
            promise.resolve(json.data)
        } else if message.name == "reject" {
            let json = try! JSONDecoder().decode(JsResult.self, from: (message.body as! String).data(using: .utf8)!)
            guard let promise = asyncPool[json.id] else {
                return
            }
            asyncPool.removeValue(forKey: json.id)
            promise.reject("error", json.data, nil)
        }
    }
}

