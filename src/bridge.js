var wasm = {}
var promise = {}
function instantiate (id, initScripts, bytes) {
  var module = eval(initScripts)
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
