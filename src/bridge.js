// android
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

// ios
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
    window.webkit.messageHandlers.resolve.postMessage(JSON.stringify(
      { id: id, data: JSON.stringify(Object.keys(WASMModule)) }));
  }).catch(function (e) {
    delete promise[id];
    window.webkit.messageHandlers.reject.postMessage(
      JSON.stringify({ id: id, data: e.toString() }));
  });
  return true;
}
