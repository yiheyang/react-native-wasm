// android
var wasm = {};
var promise = {};

function instantiate (id, bytes) {
  promise[id] = window.Module({
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
    android.resolve(id, JSON.stringify(Object.keys(res)));
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
  promise[id] = window.Module({
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
