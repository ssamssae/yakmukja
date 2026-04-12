#import <Flutter/Flutter.h>
#import <objc/runtime.h>

@interface FlutterViewController (YakmukjaCrashFix)
@end

@implementation FlutterViewController (YakmukjaCrashFix)

+ (void)load {
  SEL sel = NSSelectorFromString(@"createTouchRateCorrectionVSyncClientIfNeeded");
  Method m = class_getInstanceMethod(self, sel);
  if (m == NULL) {
    return;
  }
  IMP noop = imp_implementationWithBlock(^(__unused id _self) {
    // no-op: works around an iOS 26 + ProMotion crash inside
    // -[VSyncClient initWithTaskRunner:callback:] that was reached from
    // createTouchRateCorrectionVSyncClientIfNeeded during viewDidLoad.
  });
  method_setImplementation(m, noop);
}

@end
