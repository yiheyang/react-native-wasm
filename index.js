import { NativeModules, NativeEventEmitter, Platform } from "react-native";

if (Platform.OS === "ios") {
  const { Wasm } = NativeModules;
  const eventEmitter = new NativeEventEmitter(Wasm);

  const instantiate = (buffer) =>
    new Promise((resolve, reject) => {
      const subResolve = eventEmitter.addListener("resolve", (res) => {
        subResolve.remove();
        try {
          const { id, keys } = JSON.parse(res);
          resolve({
            instance: {
              exports: JSON.parse(keys).reduce((acc, k) => {
                acc[k] = (...args) => Wasm.call(id, k, JSON.stringify(args));
                return acc;
              }, {}),
            },
            module: {},
          });
        } catch (e) {
          reject(e);
        }
      });

      Wasm.instantiate(buffer.toString())
        .then((res) => {
          if (!res) {
            subResolve.remove();
            reject("failed to instantiate WebAssembly");
          }
        })
        .catch((e) => {
          subResolve.remove();
          reject(e);
        });
    });

  const wasmPolyfill = {
    instantiate: (buffer, importObject) => {
      return instantiate(buffer);
    },
    // `instantiateStreaming` do not work because `FileReader.readAsArrayBuffer` is not supported by React Native currently.
    // instantiateStreaming: (response, importObject) =>
    //   Promise.resolve(response.arrayBuffer()).then((bytes) =>
    //     instantiate(bytes)
    //   ),
    compile: (bytes) => {},
    compileStreaming: () => {},
    validate: () => true,
  };

  window.WebAssembly = window.WebAssembly || wasmPolyfill;
}
