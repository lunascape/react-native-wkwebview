#import "CRAWKWebViewManager.h"

#import "CRAWKWebView.h"
#import "WKProcessPool+SharedProcessPool.h"
#import <React/RCTBridge.h>
#import <React/RCTUtils.h>
#import <React/RCTUIManager.h>
#import <React/UIView+React.h>
#import <React/RCTBridgeModule.h>

#import <WebKit/WebKit.h>

@implementation RCTConvert (UIScrollView)

#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000 /* __IPHONE_11_0 */
RCT_ENUM_CONVERTER(UIScrollViewContentInsetAdjustmentBehavior, (@{
                                                                  @"automatic": @(UIScrollViewContentInsetAdjustmentAutomatic),
                                                                  @"scrollableAxes": @(UIScrollViewContentInsetAdjustmentScrollableAxes),
                                                                  @"never": @(UIScrollViewContentInsetAdjustmentNever),
                                                                  @"always": @(UIScrollViewContentInsetAdjustmentAlways),
                                                                  }), UIScrollViewContentInsetAdjustmentNever, integerValue)
#endif

RCT_ENUM_CONVERTER(UIScrollViewKeyboardDismissMode, (@{
                                                      @"none": @(UIScrollViewKeyboardDismissModeNone),
                                                      @"on-drag": @(UIScrollViewKeyboardDismissModeOnDrag),
                                                      @"interactive": @(UIScrollViewKeyboardDismissModeInteractive),
                                                      }), UIScrollViewKeyboardDismissModeNone, integerValue)

@end

@interface CRAWKWebViewManager () <CRAWKWebViewDelegate>

@end

@implementation CRAWKWebViewManager
{
  NSMutableDictionary* shouldStartRequestConditions;
  NSConditionLock* createNewWindowCondition;
  BOOL createNewWindowResult;
  CRAWKWebView* newWindow;
}

RCT_EXPORT_MODULE()

- (id)init {
    self = [super init];
    
    shouldStartRequestConditions = @{}.mutableCopy;
    return self;
}

- (UIView *)view
{
  CRAWKWebView *webView = newWindow ? newWindow : [[CRAWKWebView alloc] initWithProcessPool:[WKProcessPool sharedProcessPool]];
  webView.delegate = self;
  newWindow = nil;
  return webView;
}

RCT_EXPORT_VIEW_PROPERTY(source, NSDictionary)
RCT_REMAP_VIEW_PROPERTY(bounces, _webView.scrollView.bounces, BOOL)
RCT_REMAP_VIEW_PROPERTY(pagingEnabled, _webView.scrollView.pagingEnabled, BOOL)
RCT_REMAP_VIEW_PROPERTY(scrollEnabled, _webView.scrollView.scrollEnabled, BOOL)
RCT_REMAP_VIEW_PROPERTY(keyboardDismissMode, _webView.scrollView.keyboardDismissMode, UIScrollViewKeyboardDismissMode)
RCT_REMAP_VIEW_PROPERTY(directionalLockEnabled, _webView.scrollView.directionalLockEnabled, BOOL)
RCT_REMAP_VIEW_PROPERTY(allowsBackForwardNavigationGestures, _webView.allowsBackForwardNavigationGestures, BOOL)
RCT_EXPORT_VIEW_PROPERTY(injectJavaScriptForMainFrameOnly, BOOL)
RCT_EXPORT_VIEW_PROPERTY(injectedJavaScriptForMainFrameOnly, BOOL)
RCT_EXPORT_VIEW_PROPERTY(injectJavaScript, NSString)
RCT_EXPORT_VIEW_PROPERTY(injectedJavaScript, NSString)
RCT_EXPORT_VIEW_PROPERTY(openNewWindowInWebView, BOOL)
RCT_EXPORT_VIEW_PROPERTY(contentInset, UIEdgeInsets)
RCT_EXPORT_VIEW_PROPERTY(automaticallyAdjustContentInsets, BOOL)
RCT_EXPORT_VIEW_PROPERTY(onLoadingStart, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onLoadingFinish, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onLoadingError, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onShouldStartLoadWithRequest, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onProgress, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onMessage, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onScroll, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(hideKeyboardAccessoryView, BOOL)
RCT_EXPORT_VIEW_PROPERTY(keyboardDisplayRequiresUserAction, BOOL)
RCT_EXPORT_VIEW_PROPERTY(messagingEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(allowsLinkPreview, BOOL)
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000 /* __IPHONE_11_0 */
RCT_EXPORT_VIEW_PROPERTY(contentInsetAdjustmentBehavior, UIScrollViewContentInsetAdjustmentBehavior)
#endif
RCT_EXPORT_VIEW_PROPERTY(onNavigationResponse, RCTDirectEventBlock)

RCT_EXPORT_VIEW_PROPERTY(onNavigationStateChange, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onShouldCreateNewWindow, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(lockScroll, NSInteger)
RCT_EXPORT_VIEW_PROPERTY(scrollToTop, BOOL)
RCT_EXPORT_VIEW_PROPERTY(adjustOffset, CGPoint)

RCT_EXPORT_METHOD(goBack:(nonnull NSNumber *)reactTag)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, CRAWKWebView *> *viewRegistry) {
    CRAWKWebView *view = viewRegistry[reactTag];
    if (![view isKindOfClass:[CRAWKWebView class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting CRAWKWebView, got: %@", view);
    } else {
      [view goBack];
    }
  }];
}

RCT_EXPORT_METHOD(goForward:(nonnull NSNumber *)reactTag)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, CRAWKWebView *> *viewRegistry) {
    CRAWKWebView *view = viewRegistry[reactTag];
    if (![view isKindOfClass:[CRAWKWebView class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting CRAWKWebView, got: %@", view);
    } else {
      [view goForward];
    }
  }];
}

RCT_EXPORT_METHOD(canGoBack:(nonnull NSNumber *)reactTag
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, CRAWKWebView *> *viewRegistry) {
    CRAWKWebView *view = viewRegistry[reactTag];
    

    resolve([NSNumber numberWithBool:[view canGoBack]]);
  }];
}

RCT_EXPORT_METHOD(canGoForward:(nonnull NSNumber *)reactTag
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, CRAWKWebView *> *viewRegistry) {
    CRAWKWebView *view = viewRegistry[reactTag];
    

    resolve([NSNumber numberWithBool:[view canGoForward]]);
  }];
}

RCT_EXPORT_METHOD(reload:(nonnull NSNumber *)reactTag)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, CRAWKWebView *> *viewRegistry) {
    CRAWKWebView *view = viewRegistry[reactTag];
    if (![view isKindOfClass:[CRAWKWebView class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting CRAWKWebView, got: %@", view);
    } else {
      [view reload];
    }
  }];
}

RCT_EXPORT_METHOD(stopLoading:(nonnull NSNumber *)reactTag)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, CRAWKWebView *> *viewRegistry) {
    CRAWKWebView *view = viewRegistry[reactTag];
    if (![view isKindOfClass:[CRAWKWebView class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting CRAWKWebView, got: %@", view);
    } else {
      [view stopLoading];
    }
  }];
}

RCT_EXPORT_METHOD(postMessage:(nonnull NSNumber *)reactTag message:(NSString *)message)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, CRAWKWebView *> *viewRegistry) {
    CRAWKWebView *view = viewRegistry[reactTag];
    if (![view isKindOfClass:[CRAWKWebView class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting RCTWebView, got: %@", view);
    } else {
      [view postMessage:message];
    }
  }];
}

RCT_EXPORT_METHOD(evaluateJavaScript:(nonnull NSNumber *)reactTag
                  js:(NSString *)js
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, CRAWKWebView *> *viewRegistry) {
    CRAWKWebView *view = viewRegistry[reactTag];
    if (![view isKindOfClass:[CRAWKWebView class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting CRAWKWebView, got: %@", view);
    } else {
      [view evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (error) {
          reject(@"js_error", @"Error occurred while evaluating Javascript", error);
        } else {
          resolve(result);
        }
      }];
    }
  }];
}

RCT_EXPORT_METHOD(captureScreen:(nonnull NSNumber *)reactTag callback:(RCTResponseSenderBlock)callback)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, CRAWKWebView *> *viewRegistry) {
    CRAWKWebView *view = viewRegistry[reactTag];
    if (![view isKindOfClass:[CRAWKWebView class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting CRAWKWebView, got: %@", view);
    } else {
      [view captureScreen:callback];
    }
  }];
}

RCT_EXPORT_METHOD(capturePage:(nonnull NSNumber *)reactTag callback:(RCTResponseSenderBlock)callback)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, CRAWKWebView *> *viewRegistry) {
    CRAWKWebView *view = viewRegistry[reactTag];
    if (![view isKindOfClass:[CRAWKWebView class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting CRAWKWebView, got: %@", view);
    } else {
      [view capturePage:callback];
    }
  }];
}

RCT_EXPORT_METHOD(findInPage:(nonnull NSNumber *)reactTag searchString:(NSString *)searchString completed:(RCTResponseSenderBlock)callback)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, CRAWKWebView *> *viewRegistry) {
    CRAWKWebView *view = viewRegistry[reactTag];
    if (![view isKindOfClass:[CRAWKWebView class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting CRAWKWebView, got: %@", view);
    } else {
      NSLog(@"Search webview with string: %@", searchString);
      [view findInPage:searchString completed:callback];
    }
  }];
}

RCT_EXPORT_METHOD(printContent:(nonnull NSNumber *)reactTag) {
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, CRAWKWebView *> *viewRegistry) {
    CRAWKWebView *view = viewRegistry[reactTag];
    if (![view isKindOfClass:[CRAWKWebView class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting CRAWKWebView, got: %@", view);
    } else {
      [view printContent];
    }
  }];
}

#pragma mark - Exported synchronous methods

- (BOOL)webView:(__unused CRAWKWebView *)webView
shouldStartLoadForRequest:(NSMutableDictionary<NSString *, id> *)request
   withCallback:(RCTDirectEventBlock)callback
{
  NSConditionLock *condition = [[NSConditionLock alloc] initWithCondition:arc4random()];
  NSString* key = @(condition.condition).stringValue;
  [shouldStartRequestConditions setObject:@{@"result": @(YES), @"condition": condition} forKey:key];
  request[@"lockIdentifier"] = @(condition.condition);
  callback(request);
  
  // Block the main thread for a maximum of 250ms until the JS thread returns
  if ([condition lockWhenCondition:0 beforeDate:[NSDate dateWithTimeIntervalSinceNow:.25]]) {
    BOOL returnValue = [[[shouldStartRequestConditions objectForKey:key] objectForKey:@"result"] boolValue];
    [condition unlock];
    [shouldStartRequestConditions removeObjectForKey:key];
    return returnValue;
  } else {
    RCTLogWarn(@"Did not receive response to shouldStartLoad in time, defaulting to YES");
    return YES;
  }
}

- (CRAWKWebView*)webView:(__unused CRAWKWebView *)webView
shouldCreateNewWindow:(NSMutableDictionary<NSString *, id> *)request
  withConfiguration:(WKWebViewConfiguration*)configuration
  withCallback:(RCTDirectEventBlock)callback
{
  createNewWindowCondition = [[NSConditionLock alloc] initWithCondition:arc4random()];
  createNewWindowResult = YES;
  request[@"lockIdentifier"] = @(createNewWindowCondition.condition);
  callback(request);
  
  // Block the main thread for a maximum of 250ms until the JS thread returns
  if ([createNewWindowCondition lockWhenCondition:0 beforeDate:[NSDate dateWithTimeIntervalSinceNow:.25]]) {
    [createNewWindowCondition unlock];
    createNewWindowCondition = nil;
    if (createNewWindowResult) {
      newWindow = [[CRAWKWebView alloc] initWithConfiguration:configuration];
      return newWindow;
    } else {
      return nil;
    }
  } else {
    RCTLogWarn(@"Did not receive response to shouldCreateNewWindow in time, defaulting to YES");
    return nil;
  }
}

RCT_EXPORT_METHOD(startLoadWithResult:(BOOL)result lockIdentifier:(NSInteger)lockIdentifier)
{
  NSString* key = @(lockIdentifier).stringValue;
  NSConditionLock* condition = [[shouldStartRequestConditions objectForKey:key] objectForKey:@"condition"];
  if (condition && [condition tryLockWhenCondition:lockIdentifier]) {
    [shouldStartRequestConditions setObject:@{@"result": @(result), @"condition": condition} forKey:key];
    [condition unlockWithCondition:0];
  } else {
    RCTLogWarn(@"startLoadWithResult invoked with invalid lockIdentifier: "
               "got %zd, expected %zd", lockIdentifier, condition.condition);
  }
}

RCT_EXPORT_METHOD(createNewWindowWithResult:(BOOL)result lockIdentifier:(NSInteger)lockIdentifier)
{
  if (createNewWindowCondition && [createNewWindowCondition tryLockWhenCondition:lockIdentifier]) {
    createNewWindowResult = result;
    [createNewWindowCondition unlockWithCondition:0];
  } else {
    RCTLogWarn(@"createNewWindowWithResult invoked with invalid lockIdentifier: "
               "got %zd, expected %zd", lockIdentifier, createNewWindowCondition.condition);
  }
}

@end
