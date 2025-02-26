#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(Wasm, NSObject)

RCT_EXTERN_METHOD(instantiate:(NSString *)modId initScriptsStr:(NSString *)initScripts bytesStr:(NSString *)bytes resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(call:(NSString *)modId funcName:(NSString *)name arguments:(NSString *)args resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN__BLOCKING_SYNCHRONOUS_METHOD(callSync:(NSString *)modId funcName:(NSString *)name arguments:(NSString *)args)

@end
