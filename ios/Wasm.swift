import Foundation
import WebKit

let js: String = """
var wasm = {}
var promise = {}
function instantiate (id, bytes) {
  promise[id] = module({
    instantiateWasm: (info, successCallback) => {
      WebAssembly.instantiate(bytes, info).then((res) => {
        successCallback(res.instance)
      })
    }
  }).
    then((instance) => {
      delete promise[id]
      wasm[id] = instance
      android.resolve(id, JSON.stringify(Object.keys(instance)))
    }).
    catch(function (e) {
      delete promise[id]
      android.reject(id, e.toString())
    })
  return true
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
            self.webView.evaluateJavaScript("""
            (function(){var module = \(initScripts)})();
            """
            ) { (value, error) in
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

    @objc @discardableResult
    func callSync(_ modId: NSString, funcName name: NSString, arguments args: NSString) -> NSNumber {
        var result: NSNumber = 0
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript("""
            wasm["\(modId)"].\(name)(...\(args));
            """
            ) { (value, error) in
                // TODO handle error
                if value == nil {
                    result = 0
                } else {
                    result = value as! NSNumber
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

