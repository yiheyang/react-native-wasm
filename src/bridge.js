// android
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

// ios
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
