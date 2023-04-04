import Foundation
import WebKit

let js: String = """
var wasm = {};
var promise = {};

function instantiate (id, tid, bytes) {
  promise[tid] = self.Module(Uint8Array.from(bytes)).then(function (res) {
    var instanceMap = {};
    var instanceID = 0;
    var WASMModule = self.Module;
    WASMModule.newInstance = function (method, ...callArgs) {
      var instance = new WASMModule[method](...callArgs);
      instanceMap[instanceID++] = instance;
      return instanceID - 1;
    };
    WASMModule.freeInstance = function (_id) {
      instanceMap[_id].free();
      delete instanceMap[_id];
    };
    WASMModule.instanceCall = function (_id, method, ...callArgs) {
      return instanceMap[_id][method](...callArgs);
    };

    delete promise[tid];
    wasm[id] = WASMModule;
    window.webkit.messageHandlers.resolve.postMessage(JSON.stringify(
      { tid, data: JSON.stringify(Object.keys(WASMModule)) }));
  }).catch(function (e) {
    delete promise[tid];
    window.webkit.messageHandlers.reject.postMessage(
      JSON.stringify({ tid, data: e.toString() }));
  });
  return true;
}
"""

struct Promise {
    let resolve: RCTPromiseResolveBlock
    let reject: RCTPromiseRejectBlock
}

struct JsResult: Codable {
    let tid: String
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
    func instantiate(_ modId: NSString, tid: NSString, initScriptsStr initScripts: NSString, bytesStr bytes: NSString, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) -> Void {
        asyncPool.updateValue(Promise(resolve: resolve, reject: reject), forKey: tid as String)

        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(initScripts as String) { (value, error) in
                if error != nil {
                    self.asyncPool.removeValue(forKey: tid as String)
                    reject("error", "\(error)", nil)
                }
            }

            self.webView.evaluateJavaScript("""
            instantiate("\(modId)", "\(tid)", [\(bytes)]);
            """
            ) { (value, error) in
                if error != nil {
                    self.asyncPool.removeValue(forKey: tid as String)
                    reject("error", "\(error)", nil)
                }
            }
        }
    }

    @objc
    func call(_ modId: NSString, tid: NSString, funcName name: NSString, arguments args: NSString, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) -> Void {
        asyncPool.updateValue(Promise(resolve: resolve, reject: reject), forKey: tid as String)
        var result: NSString = ""
        var script: String
        if args == "undefined" {
            script = """
            JSON.stringify(wasm["\(modId)"].\(name)()) || "undefined";
            """
        } else {
            script = """
            JSON.stringify(wasm["\(modId)"].\(name)(...JSON.parse(`\(args)`))) || "undefined";
            """
        }

        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(script) { (value, error) in
                if error != nil {
                    self.asyncPool.removeValue(forKey: tid as String)
                    reject("error", "\(error)", nil)
                } else {
                  if value == nil {
                      result = ""
                  } else {
                      result = value as! NSString
                  }
                  self.asyncPool.removeValue(forKey: tid as String)
                  resolve(result)
                }
            }
        }
    }

    @objc @discardableResult
    func callSync(_ modId: NSString, tid: NSString, funcName name: NSString, arguments args: NSString) -> NSString {
        var result: NSString = ""
        let semaphore = DispatchSemaphore(value: 0)
        var script: String
        if args == "undefined" {
            script = """
            JSON.stringify(wasm["\(modId)"].\(name)()) || "undefined";
            """
        } else {
            script = """
            JSON.stringify(wasm["\(modId)"].\(name)(...JSON.parse(`\(args)`))) || "undefined";
            """
        }

        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(script) { (value, error) in
                if error != nil {
                    debugPrint("WASM JSBridge Error", "\(error)")
                } else {
                    if value == nil {
                        result = ""
                    } else {
                        result = value as! NSString
                    }
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
            guard let promise = asyncPool[json.tid] else {
                return
            }
            asyncPool.removeValue(forKey: json.tid)
            promise.resolve(json.data)
        } else if message.name == "reject" {
            let json = try! JSONDecoder().decode(JsResult.self, from: (message.body as! String).data(using: .utf8)!)
            guard let promise = asyncPool[json.tid] else {
                return
            }
            asyncPool.removeValue(forKey: json.tid)
            promise.reject("error", json.data, nil)
        }
    }
}
