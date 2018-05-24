#import <WebKit/WebKit.h>

#import <React/RCTEventEmitter.h>
#import <React/RCTView.h>

@class RCTWKWebView;

/**
 * Special scheme used to pass messages to the injectedJavaScript
 * code without triggering a page load. Usage:
 *
 *   window.location.href = RCTJSNavigationScheme + '://hello'
 */
extern NSString *const RCTJSNavigationScheme;

@protocol RCTWKWebViewDelegate <NSObject>

- (BOOL)webView:(RCTWKWebView *)webView
shouldStartLoadForRequest:(NSMutableDictionary<NSString *, id> *)request
   withCallback:(RCTDirectEventBlock)callback;
- (BOOL)webView:(RCTWKWebView *)webView
shouldCreateNewWindow:(NSMutableDictionary<NSString *, id> *)request
   withCallback:(RCTDirectEventBlock)callback;

@end

typedef enum {
    NoLock = 0,
    LockDirectionUp,
    LockDirectionDown,
    LockDirectionBoth
} LockScroll;

@interface RCTWKWebView : RCTView

- (instancetype)initWithProcessPool:(WKProcessPool *)processPool;

@property (nonatomic, weak) id<RCTWKWebViewDelegate> delegate;

@property (nonatomic, copy) NSDictionary *source;
@property (nonatomic, assign) UIEdgeInsets contentInset;
@property (nonatomic, assign) BOOL automaticallyAdjustContentInsets;
@property (nonatomic, assign) BOOL messagingEnabled;
@property (nonatomic, assign) BOOL allowsLinkPreview;
@property (nonatomic, assign) BOOL openNewWindowInWebView;
@property (nonatomic, assign) BOOL injectJavaScriptForMainFrameOnly;
@property (nonatomic, assign) BOOL injectedJavaScriptForMainFrameOnly;
@property (nonatomic, copy) NSString *injectJavaScript;
@property (nonatomic, copy) NSString *injectedJavaScript;
@property (nonatomic, assign) BOOL hideKeyboardAccessoryView;
@property (nonatomic, assign) BOOL keyboardDisplayRequiresUserAction;
@property (nonatomic, assign) LockScroll lockScroll;
@property (nonatomic, assign) BOOL scrollToTop;
@property (nonatomic, assign) CGPoint adjustOffset;


- (void)goForward;
- (void)goBack;
- (BOOL)canGoBack;
- (BOOL)canGoForward;
- (void)reload;
- (void)stopLoading;
- (void)postMessage:(NSString *)message;
- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(void (^)(id, NSError *error))completionHandler;
- (void)findInPage:(NSString *)searchString completed:(RCTResponseSenderBlock)callback;
- (void)captureScreen:(RCTResponseSenderBlock)callback;
- (void)capturePage:(RCTResponseSenderBlock)callback;
- (void)printContent;

@end
