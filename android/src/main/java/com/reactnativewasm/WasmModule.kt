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
import android.util.Log



const val js: String = """
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
    android.resolve(tid, JSON.stringify(Object.keys(WASMModule)));
  }).catch(function (e) {
    delete promise[tid];
    android.reject(tid, e.toString());
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
    fun instantiate(id: String, tid: String, initScripts: String, bytes: String, promise: Promise) {
        asyncPool[tid] = promise

        Handler(Looper.getMainLooper()).post(object : Runnable {
            @RequiresApi(Build.VERSION_CODES.KITKAT)
            override fun run() {
                webView.evaluateJavascript("javascript:" + initScripts, ValueCallback<String> { value ->
                    {
                        if (value == null) {
                            asyncPool.remove(tid)
                            promise.reject("failed to instantiate")
                        }
                    }
                })
                webView.evaluateJavascript("""
                    javascript:instantiate("$id", "$tid", [$bytes]);
                    """, ValueCallback<String> { value ->
                    {
                        if (value == null) {
                            asyncPool.remove(tid)
                            promise.reject("failed to instantiate")
                        }
                    }
                })
            }
        });
    }

    @ReactMethod
    fun call(id: String, tid: String, name: String, args: String, promise: Promise) {
        asyncPool[tid] = promise

        Handler(Looper.getMainLooper()).post(object : Runnable {
            @RequiresApi(Build.VERSION_CODES.KITKAT)
            override fun run() {
                val script: String
                if (args == "undefined") {
                    script = """
                        javascript:try {
                          android.resolve("$tid", JSON.stringify(wasm["$id"].$name()) || "undefined")
                        } catch (e) { android.reject("$tid", e.toString()) };
                        """
                } else {
                    script = """
                        javascript:try {
                          android.resolve("$tid", JSON.stringify(wasm["$id"].$name(...JSON.parse(`$args`))) || "undefined")
                        } catch (e) { android.reject("$tid", e.toString()) };
                        """
                }
                webView.evaluateJavascript(script, ValueCallback<String> { value ->
                    {
                        if (value == null) {
                            asyncPool.remove(tid)
                            promise.reject("failed to call $name")
                        }
                    }
                })
            }
        });
    }

    @ReactMethod(isBlockingSynchronousMethod = true)
    fun callSync(id: String, tid: String, name: String, args: String): String {
        val latch = CountDownLatch(1)
        syncPool[tid] = latch

        Handler(context.getMainLooper()).post(object : Runnable {
            @RequiresApi(Build.VERSION_CODES.KITKAT)
            override fun run() {
                val script: String
                if (args == "undefined") {
                    script = """
                        javascript:try {
                          android.returnSync("$tid", JSON.stringify(wasm["$id"].$name()))
                        } catch (e) { android.log(e.toString()) };
                        """
                } else {
                    script = """
                        javascript:try {
                          android.returnSync("$tid", JSON.stringify(wasm["$id"].$name(...JSON.parse(`$args`))))
                        } catch (e) { android.log(e.toString()) };
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
        val result = syncResults[tid]
        syncResults.remove(tid)
        return result ?: ""
    }

    protected class JSHandler internal constructor(ctx: WasmModule, asyncPool: HashMap<String, Promise>, syncPool: HashMap<String, CountDownLatch>, syncResults: HashMap<String, String>) {
        val ctx: WasmModule = ctx
        val asyncPool: HashMap<String, Promise> = asyncPool
        val syncPool: HashMap<String, CountDownLatch> = syncPool
        val syncResults: HashMap<String, String> = syncResults

        @JavascriptInterface
        fun log(data: String) {
            Log.d("WASM JSBridge Error", data)
        }

        @JavascriptInterface
        fun resolve(tid: String, data: String) {
            val p = asyncPool[tid]
            if (p != null) {
                asyncPool.remove(tid)
                p.resolve(data)
            }
        }

        @JavascriptInterface
        fun reject(tid: String, data: String) {
            log(data)
            val p = asyncPool[tid]
            if (p != null) {
                asyncPool.remove(tid)
                p.reject(data)
            }
        }

        @JavascriptInterface
        fun returnSync(tid: String, data: String) {
            val l = syncPool[tid]
            if (l != null) {
                syncPool.remove(tid)
                syncResults[tid] = data
                l.countDown()
            }
        }
    }
}
