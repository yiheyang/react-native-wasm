import { NativeModules } from 'react-native';

const { Wasm } = NativeModules;

class WasmInstance {
  constructor (id, keys) {
    JSON.parse(keys).map(k => {
      this[k] = (...args) => {
        return new Promise((resolve, reject) => {
          const tid = generateId();
          Wasm.call(id, tid, k, JSON.stringify(args) || 'undefined').
            then((result) => {
              if (result === 'undefined') {
                resolve();
              } else {
                resolve(JSON.parse(result));
              }
            }).
            catch(err => {
              reject(err);
            });
        });
      };
    });
  }
}

const generateId = () => {
  return (
    new Date().getTime().toString(16) +
    Math.floor(1000 * Math.random()).toString(16)
  );
};

const instantiate = (initScripts, buffer) =>
  new Promise((resolve, reject) => {
    const id = generateId();
    const tid = generateId();

    Wasm.instantiate(id, tid, initScripts, buffer.toString()).then((keys) => {
      if (!keys) {
        reject('failed to get exports');
      } else {
        resolve(new WasmInstance(id, keys));
      }
    }).catch((e) => {
      reject(e);
    });
  });

export const WebAssembly = {
  initModule: (initScripts, buffer) => {
    return instantiate(initScripts, buffer);
  }
};
