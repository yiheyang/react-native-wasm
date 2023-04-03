package com.reactnativewasm

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.ValueCallback
import android.webkit.WebView
import androidx.annotation.RequiresApi
import com.facebook.react.bridge.*
import java.util.concurrent.CountDownLatch
import kotlin.collections.HashMap


const val js: String = """
var wasm = {};
var promise = {};

function instantiate (id, bytes) {
  promise[id] = self.Module(Uint8Array.from(bytes)).then(function (res) {
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

    delete promise[id];
    wasm[id] = WASMModule;
    android.resolve(id, JSON.stringify(Object.keys(WASMModule)));
  }).catch(function (e) {
    delete promise[id];
    android.reject(id, e.toString());
  });
  return true;
}
"""

class WasmModule(reactContext: ReactApplicationContext) : ReactContextBaseJavaModule(reactContext) {

    private val context: ReactContext = reactContext
    lateinit var webView: WebView;
    val asyncPool = HashMap<String, Promise>()
    val syncPool = HashMap<String, CountDownLatch>()
    val syncResults = HashMap<String, String>()

    init {
        val self = this;
        Handler(Looper.getMainLooper()).post(object : Runnable {
            @RequiresApi(Build.VERSION_CODES.KITKAT)
            override fun run() {
                webView = WebView(context);
                webView.settings.javaScriptEnabled = true
                webView.addJavascriptInterface(JSHandler(self, asyncPool, syncPool, syncResults), "android")
                webView.evaluateJavascript("javascript:" + js, ValueCallback<String> { reply -> // NOP
                })
            }
        });
    }

    override fun getName(): String {
        return "Wasm"
    }

    @ReactMethod
    fun instantiate(id: String, initScripts: String, bytes: String, promise: Promise) {
        asyncPool[id] = promise

        Handler(Looper.getMainLooper()).post(object : Runnable {
            @RequiresApi(Build.VERSION_CODES.KITKAT)
            override fun run() {
                webView.evaluateJavascript("javascript:" + initScripts, ValueCallback<String> { value ->
                    {
                        if (value == null) {
                            asyncPool.remove(id)
                            promise.reject("failed to instantiate")
                        }
                    }
                })
                webView.evaluateJavascript("""
                    javascript:instantiate("$id", [$bytes]);
                    """, ValueCallback<String> { value ->
                    {
                        if (value == null) {
                            asyncPool.remove(id)
                            promise.reject("failed to instantiate")
                        }
                    }
                })
            }
        });
    }

    @ReactMethod
    fun call(id: String, name: String, args: String, promise: Promise) {
        asyncPool[id] = promise

        Handler(Looper.getMainLooper()).post(object : Runnable {
            @RequiresApi(Build.VERSION_CODES.KITKAT)
            override fun run() {
                val script: String
                if (args == "undefined") {
                    script = """
                        javascript:android.resolve("$id", JSON.stringify(wasm["$id"].$name()));
                        """
                } else {
                    script = """
                        javascript:android.resolve("$id", JSON.stringify(wasm["$id"].$name(...JSON.parse(`$args`))));
                        """
                }
                webView.evaluateJavascript(script, ValueCallback<String> { value ->
                    {
                        if (value == null) {
                            asyncPool.remove(id)
                            promise.reject("failed to call $name")
                        }
                    }
                })
            }
        });
    }

    @ReactMethod(isBlockingSynchronousMethod = true)
    fun callSync(id: String, name: String, args: String): String {
        val latch = CountDownLatch(1)
        syncPool[id] = latch

        Handler(context.getMainLooper()).post(object : Runnable {
            @RequiresApi(Build.VERSION_CODES.KITKAT)
            override fun run() {
                val script: String
                if (args == "undefined") {
                    script = """
                        javascript:android.returnSync("$id", JSON.stringify(wasm["$id"].$name()));
                        """
                } else {
                    script = """
                        javascript:android.returnSync("$id", JSON.stringify(wasm["$id"].$name(...JSON.parse(`$args`))));
                        """
                }
                webView.evaluateJavascript(script, ValueCallback<String> { value ->
                    {
                        // NOP
                    }
                })
            }
        });

        latch.await()
        val result = syncResults[id]
        syncResults.remove(id)
        return result ?: ""
    }

    protected class JSHandler internal constructor(ctx: WasmModule, asyncPool: HashMap<String, Promise>, syncPool: HashMap<String, CountDownLatch>, syncResults: HashMap<String, String>) {
        val ctx: WasmModule = ctx
        val asyncPool: HashMap<String, Promise> = asyncPool
        val syncPool: HashMap<String, CountDownLatch> = syncPool
        val syncResults: HashMap<String, String> = syncResults

        @JavascriptInterface
        fun resolve(id: String, data: String) {
            val p = asyncPool[id]
            if (p != null) {
                asyncPool.remove(id)
                p.resolve(data)
            }
        }

        @JavascriptInterface
        fun reject(id: String, data: String) {
            val p = asyncPool[id]
            if (p != null) {
                asyncPool.remove(id)
                p.reject(data)
            }
        }

        @JavascriptInterface
        fun returnSync(id: String, data: String) {
            val l = syncPool[id]
            if (l != null) {
                syncPool.remove(id)
                syncResults[id] = data
                l.countDown()
            }
        }
    }
}
