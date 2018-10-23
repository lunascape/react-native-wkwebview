#import "CRAWKWebView.h"

#import "WeakScriptMessageDelegate.h"

#import <UIKit/UIKit.h>

#import <React/RCTAutoInsetsProtocol.h>
#import <React/RCTConvert.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTLog.h>
#import <React/RCTUtils.h>
#import <React/RCTView.h>
#import <React/UIView+React.h>

#import <objc/runtime.h>

#import "WKWebView+BrowserHack.h"
#import "WKWebView+Highlight.h"
#import "WKWebView+Capture.h"

#define LocalizeString(key) (NSLocalizedStringFromTableInBundle(key, @"Localizable", resourceBundle, nil))

// runtime trick to remove WKWebView keyboard default toolbar
// see: http://stackoverflow.com/questions/19033292/ios-7-uiwebview-keyboard-issue/19042279#19042279
@interface _SwizzleHelperWK : NSObject @end
@implementation _SwizzleHelperWK
-(id)inputAccessoryView
{
  return nil;
}
@end

@interface CRAWKWebView () <WKNavigationDelegate, RCTAutoInsetsProtocol, WKScriptMessageHandler, WKUIDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, copy) RCTDirectEventBlock onLoadingStart;
@property (nonatomic, copy) RCTDirectEventBlock onLoadingFinish;
@property (nonatomic, copy) RCTDirectEventBlock onLoadingError;
@property (nonatomic, copy) RCTDirectEventBlock onShouldStartLoadWithRequest;
@property (nonatomic, copy) RCTDirectEventBlock onProgress;
@property (nonatomic, copy) RCTDirectEventBlock onMessage;
@property (nonatomic, copy) RCTDirectEventBlock onScroll;
@property (nonatomic, copy) RCTDirectEventBlock onNavigationResponse;
@property (assign) BOOL sendCookies;
@property (nonatomic, strong) WKUserScript *atStartScript;
@property (nonatomic, strong) WKUserScript *atEndScript;
@property (nonatomic, copy) RCTDirectEventBlock onNavigationStateChange;
@property (nonatomic, copy) RCTDirectEventBlock onShouldCreateNewWindow;

@end

@implementation CRAWKWebView
{
  WKWebView *_webView;
  BOOL _injectJavaScriptForMainFrameOnly;
  BOOL _injectedJavaScriptForMainFrameOnly;
  NSString *_injectJavaScript;
  NSString *_injectedJavaScript;
  BOOL longPress;
  NSBundle* resourceBundle;
  CGPoint lastOffset;
  BOOL decelerating;
  BOOL dragging;
  BOOL scrollingToTop;
  BOOL isDisplayingError;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  return self = [super initWithFrame:frame];
}

RCT_NOT_IMPLEMENTED(- (instancetype)initWithCoder:(NSCoder *)aDecoder)

- (instancetype)initWithProcessPool:(WKProcessPool *)processPool
{
  if(self = [self initWithFrame:CGRectZero])
  {
    super.backgroundColor = [UIColor clearColor];
    _automaticallyAdjustContentInsets = YES;
    _contentInset = UIEdgeInsetsZero;
    
    NSString* bundlePath = [[NSBundle mainBundle] pathForResource:@"Scripts" ofType:@"bundle"];
    resourceBundle = [NSBundle bundleWithPath:bundlePath];
    
    WKWebViewConfiguration* config = [[WKWebViewConfiguration alloc] init];
    config.processPool = processPool;
    WKUserContentController* userController = [[WKUserContentController alloc]init];
    [userController addScriptMessageHandler:[[WeakScriptMessageDelegate alloc] initWithDelegate:self] name:@"reactNative"];
    config.userContentController = userController;
    
    _webView = [[WKWebView alloc] initWithFrame:self.bounds configuration:config];
    _webView.UIDelegate = self;
    _webView.navigationDelegate = self;
    _webView.scrollView.delegate = self;
    
    _webView.scrollView.decelerationRate = UIScrollViewDecelerationRateNormal;
    lastOffset = _webView.scrollView.contentOffset;
    
    // add pull down to reload feature in scrollview of webview - Fix issue 1174
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(handleRefresh:) forControlEvents:UIControlEventValueChanged];
    [_webView.scrollView addSubview:refreshControl];
    
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000 /* __IPHONE_11_0 */
    // `contentInsetAdjustmentBehavior` is only available since iOS 11.
    // We set the default behavior to "never" so that iOS
    // doesn't do weird things to UIScrollView insets automatically
    // and keeps it as an opt-in behavior.
    if ([_webView.scrollView respondsToSelector:@selector(setContentInsetAdjustmentBehavior:)]) {
      _webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
#endif
    [self setupPostMessageScript];
    [_webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
    [_webView addObserver:self forKeyPath:@"title" options:NSKeyValueObservingOptionNew context:nil];
    [_webView addObserver:self forKeyPath:@"loading" options:NSKeyValueObservingOptionNew context:nil];
    [_webView addObserver:self forKeyPath:@"canGoBack" options:NSKeyValueObservingOptionNew context:nil];
    [_webView addObserver:self forKeyPath:@"canGoForward" options:NSKeyValueObservingOptionNew context:nil];
    [_webView addObserver:self forKeyPath:@"URL" options:NSKeyValueObservingOptionNew context:nil];
    [self addSubview:_webView];
    
    UILongPressGestureRecognizer* longGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
    longGesture.delegate = self;
    [_webView addGestureRecognizer:longGesture];
  }
  return self;
}

- (void)longPressed:(UILongPressGestureRecognizer*)sender {
  if (sender.state == UIGestureRecognizerStateBegan) {
    longPress = YES;
    sender.enabled = NO;
    
    NSUInteger touchCount = [sender numberOfTouches];
    if (touchCount) {
      CGPoint point = [sender locationOfTouch:0 inView:sender.view];
      if ([_webView respondsToSelector:@selector(respondToTapAndHoldAtLocation:)]) {
        NSDictionary* urlResult = [_webView respondToTapAndHoldAtLocation:point];
        if (urlResult.allKeys.count == 0) {
          longPress = NO;
        }
        _onMessage(@{@"name":@"reactNative", @"body": @{@"type":@"contextMenu", @"data":urlResult}});
      }
    }
  } else if (sender.state == UIGestureRecognizerStateCancelled) {
    sender.enabled = YES;
  }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
  return YES;
}

- (void)setInjectJavaScript:(NSString *)injectJavaScript {
  _injectJavaScript = injectJavaScript;
  self.atStartScript = [[WKUserScript alloc] initWithSource:injectJavaScript
                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                           forMainFrameOnly:_injectJavaScriptForMainFrameOnly];
  [self resetupScripts];
}

- (void)setInjectedJavaScript:(NSString *)script {
  _injectedJavaScript = script;
  self.atEndScript = [[WKUserScript alloc] initWithSource:script
                                            injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                         forMainFrameOnly:_injectedJavaScriptForMainFrameOnly];
  [self resetupScripts];
}

- (void)setInjectedJavaScriptForMainFrameOnly:(BOOL)injectedJavaScriptForMainFrameOnly {
  _injectedJavaScriptForMainFrameOnly = injectedJavaScriptForMainFrameOnly;
  if (_injectedJavaScript != nil) {
    [self setInjectedJavaScript:_injectedJavaScript];
  }
}

- (void)setInjectJavaScriptForMainFrameOnly:(BOOL)injectJavaScriptForMainFrameOnly {
  _injectJavaScriptForMainFrameOnly = injectJavaScriptForMainFrameOnly;
  if (_injectJavaScript != nil) {
    [self setInjectJavaScript:_injectJavaScript];
  }
}

- (void)setMessagingEnabled:(BOOL)messagingEnabled {
  _messagingEnabled = messagingEnabled;
  [self setupPostMessageScript];
}

- (void)resetupScripts {
  [_webView.configuration.userContentController removeAllUserScripts];
  [self setupPostMessageScript];
  if (self.atStartScript) {
    [_webView.configuration.userContentController addUserScript:self.atStartScript];
  }
  if (self.atEndScript) {
    [_webView.configuration.userContentController addUserScript:self.atEndScript];
  }
}

- (void)setupPostMessageScript {
  if (_messagingEnabled) {
    NSString *source = @"window.originalPostMessage = window.postMessage;"
    "window.postMessage = function(message, targetOrigin, transfer) {"
      "window.webkit.messageHandlers.reactNative.postMessage(message);"
      "if (typeof targetOrigin !== 'undefined') {"
        "window.originalPostMessage(message, targetOrigin, transfer);"
      "}"
    "};";
    WKUserScript *script = [[WKUserScript alloc] initWithSource:source
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                               forMainFrameOnly:_injectedJavaScriptForMainFrameOnly];
    [_webView.configuration.userContentController addUserScript:script];
  }
}

- (void)loadRequest:(NSURLRequest *)request
{
  isDisplayingError = NO;
  if (request.URL && _sendCookies) {
    NSDictionary *cookies = [NSHTTPCookie requestHeaderFieldsWithCookies:[[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:request.URL]];
    if ([cookies objectForKey:@"Cookie"]) {
      NSMutableURLRequest *mutableRequest = request.mutableCopy;
      [mutableRequest addValue:cookies[@"Cookie"] forHTTPHeaderField:@"Cookie"];
      request = mutableRequest;
    }
  }
  
  [_webView loadRequest:request];
}

- (void)setLockScroll:(LockScroll)lockScroll {
  _lockScroll = lockScroll;
}

- (void)setScrollToTop:(BOOL)scrollToTop {
  _webView.scrollView.scrollsToTop = scrollToTop;
}

- (void)setAdjustOffset:(CGPoint)adjustOffset {
  CGRect scrollBounds = _webView.scrollView.bounds;
  scrollBounds.origin = CGPointMake(0, _webView.scrollView.contentOffset.y + adjustOffset.y);;
  _webView.scrollView.bounds = scrollBounds;
  
  lastOffset = _webView.scrollView.contentOffset;
}

-(void)setAllowsLinkPreview:(BOOL)allowsLinkPreview
{
  if ([_webView respondsToSelector:@selector(allowsLinkPreview)]) {
    _webView.allowsLinkPreview = allowsLinkPreview;
  }
}

-(void)setHideKeyboardAccessoryView:(BOOL)hideKeyboardAccessoryView
{
  if (!hideKeyboardAccessoryView) {
    return;
  }
  
  UIView* subview;
  for (UIView* view in _webView.scrollView.subviews) {
    if([[view.class description] hasPrefix:@"WKContent"])
      subview = view;
  }
  
  if(subview == nil) return;
  
  NSString* name = [NSString stringWithFormat:@"%@_SwizzleHelperWK", subview.class.superclass];
  Class newClass = NSClassFromString(name);
  
  if(newClass == nil)
  {
    newClass = objc_allocateClassPair(subview.class, [name cStringUsingEncoding:NSASCIIStringEncoding], 0);
    if(!newClass) return;
    
    Method method = class_getInstanceMethod([_SwizzleHelperWK class], @selector(inputAccessoryView));
    class_addMethod(newClass, @selector(inputAccessoryView), method_getImplementation(method), method_getTypeEncoding(method));
    
    objc_registerClassPair(newClass);
  }
  
  object_setClass(subview, newClass);
}

// https://github.com/Telerik-Verified-Plugins/WKWebView/commit/04e8296adeb61f289f9c698045c19b62d080c7e3
// https://stackoverflow.com/a/48623286/3297914
-(void)setKeyboardDisplayRequiresUserAction:(BOOL)keyboardDisplayRequiresUserAction
{
  if (!keyboardDisplayRequiresUserAction) {
    Class class = NSClassFromString(@"WKContentView");
    NSOperatingSystemVersion iOS_11_3_0 = (NSOperatingSystemVersion){11, 3, 0};
    
    if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion: iOS_11_3_0]) {
      SEL selector = sel_getUid("_startAssistingNode:userIsInteracting:blurPreviousNode:changingActivityState:userObject:");
      Method method = class_getInstanceMethod(class, selector);
      IMP original = method_getImplementation(method);
      IMP override = imp_implementationWithBlock(^void(id me, void* arg0, BOOL arg1, BOOL arg2, BOOL arg3, id arg4) {
        ((void (*)(id, SEL, void*, BOOL, BOOL, BOOL, id))original)(me, selector, arg0, TRUE, arg2, arg3, arg4);
      });
      method_setImplementation(method, override);
    } else {
      SEL selector = sel_getUid("_startAssistingNode:userIsInteracting:blurPreviousNode:userObject:");
      Method method = class_getInstanceMethod(class, selector);
      IMP original = method_getImplementation(method);
      IMP override = imp_implementationWithBlock(^void(id me, void* arg0, BOOL arg1, BOOL arg2, id arg3) {
        ((void (*)(id, SEL, void*, BOOL, BOOL, id))original)(me, selector, arg0, TRUE, arg2, arg3);
      });
      method_setImplementation(method, override);
    }
  }
}

#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000 /* __IPHONE_11_0 */
- (void)setContentInsetAdjustmentBehavior:(UIScrollViewContentInsetAdjustmentBehavior)behavior
{
  // `contentInsetAdjustmentBehavior` is available since iOS 11.
  if ([_webView.scrollView respondsToSelector:@selector(setContentInsetAdjustmentBehavior:)]) {
    CGPoint contentOffset = _webView.scrollView.contentOffset;
    _webView.scrollView.contentInsetAdjustmentBehavior = behavior;
    _webView.scrollView.contentOffset = contentOffset;
  }
}
#endif

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
  if (_onMessage) {
    NSMutableDictionary<NSString *, id> *event = [self baseEvent];
    [event addEntriesFromDictionary: @{
                                       @"data": message.body,
                                       @"name": message.name
                                       }];
    _onMessage(event);
  }
}

- (void)goForward
{
  [_webView goForward];
}

- (void)evaluateJavaScript:(NSString *)javaScriptString
         completionHandler:(void (^)(id, NSError *error))completionHandler
{
  [_webView evaluateJavaScript:javaScriptString completionHandler:completionHandler];
}

- (void)postMessage:(NSString *)message
{
  NSDictionary *eventInitDict = @{
                                  @"data": message,
                                  };
  NSString *source = [NSString
                      stringWithFormat:@"document.dispatchEvent(new MessageEvent('message', %@));",
                      RCTJSONStringify(eventInitDict, NULL)
                      ];
  [_webView evaluateJavaScript:source completionHandler:nil];
}


- (void)goBack
{
  [_webView goBack];
}

- (BOOL)canGoBack
{
  return [_webView canGoBack];
}

- (BOOL)canGoForward
{
  return [_webView canGoForward];
}

- (void)reload
{
  [_webView reload];
}

- (void)stopLoading
{
  [_webView stopLoading];
}

- (void)setSource:(NSDictionary *)source
{
  if (![_source isEqualToDictionary:source]) {
    _source = [source copy];
    _sendCookies = [source[@"sendCookies"] boolValue];
    if ([source[@"customUserAgent"] length] != 0 && [_webView respondsToSelector:@selector(setCustomUserAgent:)]) {
      [_webView setCustomUserAgent:source[@"customUserAgent"]];
    }
    
    // Allow loading local files:
    // <WKWebView source={{ file: RNFS.MainBundlePath + '/data/index.html', allowingReadAccessToURL: RNFS.MainBundlePath }} />
    // Only works for iOS 9+. So iOS 8 will simply ignore those two values
    NSString *file = [RCTConvert NSString:source[@"file"]];
    NSString *allowingReadAccessToURL = [RCTConvert NSString:source[@"allowingReadAccessToURL"]];
    
    if (file && [_webView respondsToSelector:@selector(loadFileURL:allowingReadAccessToURL:)]) {
      NSURL *fileURL = [RCTConvert NSURL:file];
      NSURL *baseURL = [RCTConvert NSURL:allowingReadAccessToURL];
      [_webView loadFileURL:fileURL allowingReadAccessToURL:baseURL];
      return;
    }
    
    // Check for a static html source first
    NSString *html = [RCTConvert NSString:source[@"html"]];
    if (html) {
      NSURL *baseURL = [RCTConvert NSURL:source[@"baseUrl"]];
      if (!baseURL) {
        baseURL = [NSURL URLWithString:@"about:blank"];
      }
      [_webView loadHTMLString:html baseURL:baseURL];
      return;
    }
    
    NSURLRequest *request = [RCTConvert NSURLRequest:source];
    // Because of the way React works, as pages redirect, we actually end up
    // passing the redirect urls back here, so we ignore them if trying to load
    // the same url. We'll expose a call to 'reload' to allow a user to load
    // the existing page.
    if ([request.URL isEqual:_webView.URL]) {
      return;
    }
    if (!request.URL) {
      // Clear the webview
      [_webView loadHTMLString:@"" baseURL:nil];
      return;
    }
    [self loadRequest:request];
  }
}

- (void)findInPage:(NSString *)searchString completed:(RCTResponseSenderBlock)callback {
  if (searchString && searchString.length > 0) {
    [_webView removeAllHighlights];
    NSInteger results = [_webView highlightAllOccurencesOfString:searchString];
    [_webView scrollToHighlightTop];
    callback(@[@(results)]);
  }
}

- (void)captureScreen:(RCTResponseSenderBlock)callback {
  [_webView contentFrameCapture:^(UIImage *capturedImage) {
    NSDate *date = [NSDate new];
    NSString *fileName = [NSString stringWithFormat:@"%f.png",date.timeIntervalSince1970];
    NSString * path = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    NSData * binaryImageData = UIImagePNGRepresentation(capturedImage);
    BOOL isWrited = [binaryImageData writeToFile:path atomically:YES];
    if (isWrited) {
      callback(@[path]);
    }
  }];
}

- (void)capturePage:(RCTResponseSenderBlock)callback {
  [_webView contentScrollCapture:^(UIImage *capturedImage) {
    NSDate *date = [NSDate new];
    NSString *fileName = [NSString stringWithFormat:@"%f.png",date.timeIntervalSince1970];
    NSString * path = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    NSData * binaryImageData = UIImagePNGRepresentation(capturedImage);
    BOOL isWrited = [binaryImageData writeToFile:path atomically:YES];
    if (isWrited) {
      callback(@[path]);
    }
  }];
}

- (void)printContent {
  UIPrintInteractionController *controller = [UIPrintInteractionController sharedPrintController];
  UIPrintInfo *printInfo = [UIPrintInfo printInfo];
  printInfo.outputType = UIPrintInfoOutputGeneral;
  printInfo.jobName = _webView.URL.absoluteString;
  printInfo.duplex = UIPrintInfoDuplexLongEdge;
  controller.printInfo = printInfo;
  controller.showsPageRange = YES;
  
  UIViewPrintFormatter *viewFormatter = [_webView viewPrintFormatter];
  viewFormatter.startPage = 0;
  viewFormatter.contentInsets = UIEdgeInsetsMake(25.0, 25.0, 25.0, 25.0);
  controller.printFormatter = viewFormatter;
  
  [controller presentAnimated:YES completionHandler:^(UIPrintInteractionController * _Nonnull printInteractionController, BOOL completed, NSError * _Nullable error) {
    if (!completed || error) {
      NSLog(@"Print FAILED! with error: %@", error.localizedDescription);
    }
  }];
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  _webView.frame = self.bounds;
}

- (void)setContentInset:(UIEdgeInsets)contentInset
{
  _contentInset = contentInset;
  [RCTView autoAdjustInsetsForView:self
                    withScrollView:_webView.scrollView
                      updateOffset:NO];
}

- (void)setBackgroundColor:(UIColor *)backgroundColor
{
  CGFloat alpha = CGColorGetAlpha(backgroundColor.CGColor);
  self.opaque = _webView.opaque = _webView.scrollView.opaque = (alpha == 1.0);
  _webView.backgroundColor = _webView.scrollView.backgroundColor = backgroundColor;
}

- (UIColor *)backgroundColor
{
  return _webView.backgroundColor;
}

- (NSMutableDictionary<NSString *, id> *)baseEvent
{
  NSMutableDictionary<NSString *, id> *event = [[NSMutableDictionary alloc] initWithDictionary:@{
                                                                                                 @"url": _webView.URL.absoluteString ?: @"",
                                                                                                 @"loading" : @(_webView.loading),
                                                                                                 @"title": _webView.title,
                                                                                                 @"canGoBack": @(_webView.canGoBack),
                                                                                                 @"canGoForward" : @(_webView.canGoForward),
                                                                                                 @"progress" : @(_webView.estimatedProgress),
                                                                                                 }];
  
  return event;
}

- (void)refreshContentInset
{
  [RCTView autoAdjustInsetsForView:self
                    withScrollView:_webView.scrollView
                      updateOffset:YES];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
  if ([keyPath isEqualToString:@"estimatedProgress"]) {
    if (!_onProgress) {
      return;
    }
    _onProgress(@{@"progress": [change objectForKey:NSKeyValueChangeNewKey]});
  } else if ([keyPath isEqualToString:@"title"] || [keyPath isEqualToString:@"loading"] || [keyPath isEqualToString:@"canGoBack"] || [keyPath isEqualToString:@"canGoForward"] || [keyPath isEqualToString:@"URL"]) {
    if (_onNavigationStateChange) {
      _onNavigationStateChange([self baseEvent]);
    }
  }
}

-(void)handleRefresh:(UIRefreshControl *)refresh {
  // reload webview
  [_webView reload];
  [refresh endRefreshing];
}

- (void)dealloc
{
  @try {
    [_webView removeObserver:self forKeyPath:@"estimatedProgress"];
    [_webView removeObserver:self forKeyPath:@"title"];
    [_webView removeObserver:self forKeyPath:@"loading"];
    [_webView removeObserver:self forKeyPath:@"canGoBack"];
    [_webView removeObserver:self forKeyPath:@"canGoForward"];
    [_webView removeObserver:self forKeyPath:@"URL"];
    _webView.UIDelegate = nil;
    _webView.scrollView.delegate = nil;
    _webView.navigationDelegate = nil;
  }
  @catch (NSException * __unused exception) {}
}

- (NSDictionary*)onScrollEvent:(CGPoint)currentOffset moveDistance:(CGPoint)distance {
  UIScrollView* scrollView = _webView.scrollView;
  CGSize frameSize = scrollView.frame.size;
  
  NSMutableDictionary<NSString *, id> *event = [self baseEvent];
  [event addEntriesFromDictionary:@{@"contentOffset": @{@"x": @(currentOffset.x),@"y": @(currentOffset.y)}}];
  [event addEntriesFromDictionary:@{@"scroll": @{@"decelerating":@(decelerating || scrollingToTop), @"width": @(frameSize.width), @"height": @(frameSize.height)}}];
  [event addEntriesFromDictionary:@{@"contentSize": @{@"width" : @(scrollView.contentSize.width), @"height": @(scrollView.contentSize.height)}}];
  
  [event addEntriesFromDictionary:@{@"offset": @{@"dx": @(distance.x),@"dy": @(distance.y)}}];
  return event;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
  CGPoint offset = scrollView.contentOffset;
  if (!decelerating && !dragging && !scrollingToTop) {
    NSLog(@"scrollViewDidScroll dont fire event");
    lastOffset = offset;
    return;
  }
  
  CGFloat dy = offset.y - lastOffset.y;
  lastOffset = offset;
  
  CGSize frameSize = scrollView.frame.size;
  CGFloat offsetMin = 0;
  CGFloat offsetMax = scrollView.contentSize.height - frameSize.height;
  if ((lastOffset.y <= offsetMin && dy > 0) || (lastOffset.y >= offsetMax && dy < 0)) {
    return;
  }
  
  NSDictionary *event = [self onScrollEvent:offset moveDistance:CGPointMake(offset.x - lastOffset.x, dy)];
  _onMessage(@{@"name":@"reactNative", @"body": @{@"type":@"onScroll", @"data":event}});
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
  decelerating = decelerate;
  dragging = NO;
  
  NSDictionary *event = [self onScrollEvent:scrollView.contentOffset moveDistance:CGPointMake(0, 0)];
  _onMessage(@{@"name":@"reactNative", @"body": @{@"type":@"onScrollEndDrag", @"data":event}});
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
  decelerating = NO;
  
  NSDictionary *event = [self onScrollEvent:scrollView.contentOffset moveDistance:CGPointMake(0, 0)];
  _onMessage(@{@"name":@"reactNative", @"body": @{@"type":@"onScrollEndDecelerating", @"data":event}});
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
  decelerating = NO;
  dragging = YES;
  
  NSDictionary *event = [self onScrollEvent:scrollView.contentOffset moveDistance:CGPointMake(0, 0)];
  _onMessage(@{@"name":@"reactNative", @"body": @{@"type":@"onScrollBeginDrag", @"data":event}});
}

- (BOOL)scrollViewShouldScrollToTop:(UIScrollView *)scrollView {
  scrollingToTop = _webView.scrollView.scrollsToTop;
  return _webView.scrollView.scrollsToTop;
}

- (void)scrollViewDidScrollToTop:(UIScrollView *)scrollView {
  scrollingToTop = NO;
  
  NSDictionary *event = [self onScrollEvent:scrollView.contentOffset moveDistance:CGPointMake(0, 0)];
  _onMessage(@{@"name":@"reactNative", @"body": @{@"type":@"onScrollEndDecelerating", @"data":event}});
  // NSDictionary *event = @{
  //                         @"contentOffset": @{
  //                             @"x": @(scrollView.contentOffset.x),
  //                             @"y": @(scrollView.contentOffset.y)
  //                             },
  //                         @"contentInset": @{
  //                             @"top": @(scrollView.contentInset.top),
  //                             @"left": @(scrollView.contentInset.left),
  //                             @"bottom": @(scrollView.contentInset.bottom),
  //                             @"right": @(scrollView.contentInset.right)
  //                             },
  //                         @"contentSize": @{
  //                             @"width": @(scrollView.contentSize.width),
  //                             @"height": @(scrollView.contentSize.height)
  //                             },
  //                         @"layoutMeasurement": @{
  //                             @"width": @(scrollView.frame.size.width),
  //                             @"height": @(scrollView.frame.size.height)
  //                             },
  //                         @"zoomScale": @(scrollView.zoomScale ?: 1),
  //                         };
  // _onScroll(event);
}

#pragma mark - WKNavigationDelegate methods

- (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential))completionHandler {
  NSString* authMethod = challenge.protectionSpace.authenticationMethod;
  if ([authMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
    @try {
      [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
    } @catch (NSException *exception) {
      NSLog(@"%@", exception.description);
    } @finally {
      completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
  } else if ([authMethod isEqualToString:NSURLAuthenticationMethodHTTPBasic]) {
    UIAlertController* alertView = [UIAlertController alertControllerWithTitle:[LocalizeString(@"Login_title") stringByReplacingOccurrencesOfString:@"%s" withString:challenge.protectionSpace.host] message:@"" preferredStyle:UIAlertControllerStyleAlert];
    [alertView addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
      textField.placeholder = LocalizeString(@"Username");
    }];
    [alertView addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
      textField.placeholder = LocalizeString(@"Password");
      textField.secureTextEntry = YES;
    }];
    [alertView addAction:[UIAlertAction actionWithTitle:LocalizeString(@"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
      completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
    }]];
    
    [alertView addAction:[UIAlertAction actionWithTitle:LocalizeString(@"Login") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
      UITextField *userField = alertView.textFields.firstObject;
      UITextField *passField = alertView.textFields.lastObject;
      NSURLCredential* credential = [NSURLCredential credentialWithUser:userField.text password:passField.text persistence:NSURLCredentialPersistenceForSession];
      @try {
        [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
      } @catch (NSException *exception) {
        NSLog(@"%@", exception.description);
      } @finally {
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
      }
    }]];
    [[[UIApplication sharedApplication].delegate window].rootViewController presentViewController:alertView animated:YES completion:nil];
  }
// #if DEBUG
// - (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
//   NSURLCredential * credential = [[NSURLCredential alloc] initWithTrust:[challenge protectionSpace].serverTrust];
//   completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
// }

- (void)webView:(__unused WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
  UIApplication *app = [UIApplication sharedApplication];
  NSURLRequest *request = navigationAction.request;
  NSURL* url = request.URL;
  NSString* scheme = url.scheme;
  
  if ([self decisionHandlerURL:url]) {
    _onMessage(@{@"name":@"reactNative", @"body": @{@"type":@"onOpenExternalApp", @"data":@{@"url": request.URL.absoluteString}}});
    return decisionHandler(WKNavigationActionPolicyCancel);
  }
  
  BOOL isJSNavigation = [scheme isEqualToString:RCTJSNavigationScheme];
  
  if (longPress) {
    longPress = NO;
    return decisionHandler(WKNavigationActionPolicyCancel);
  }
  
  BOOL isJSNavigation = [scheme isEqualToString:RCTJSNavigationScheme];
  
  // handle mailto and tel schemes
  if ([scheme isEqualToString:@"mailto"] || [scheme isEqualToString:@"tel"]) {
    if ([app canOpenURL:url]) {
      [app openURL:url];
      decisionHandler(WKNavigationActionPolicyCancel);
      return;
    }
  }
  
  // skip this for the JS Navigation handler
  if (!isJSNavigation && _onShouldStartLoadWithRequest) {
    NSMutableDictionary<NSString *, id> *event = [self baseEvent];
    [event addEntriesFromDictionary: @{
                                       @"url": (request.URL).absoluteString,
                                       @"navigationType": @(navigationAction.navigationType)
                                       }];
    if (![self.delegate webView:self
      shouldStartLoadForRequest:event
                   withCallback:_onShouldStartLoadWithRequest]) {
      return decisionHandler(WKNavigationActionPolicyCancel);
    }
  }
  
  if (!navigationAction.targetFrame) {
    // Open a new tab
    return decisionHandler(WKNavigationActionPolicyAllow);
  }
  
  if (_onLoadingStart) {
    // We have this check to filter out iframe requests and whatnot
    BOOL isTopFrame = [url isEqual:request.mainDocumentURL];
    if (isTopFrame) {
      NSMutableDictionary<NSString *, id> *event = [self baseEvent];
      [event addEntriesFromDictionary: @{
                                         @"url": url.absoluteString,
                                         @"navigationType": @(navigationAction.navigationType)
                                         }];
      _onLoadingStart(event);
    }
  }
  
  if (isJSNavigation) {
    decisionHandler(WKNavigationActionPolicyCancel);
  }
  else {
    decisionHandler(WKNavigationActionPolicyAllow);
  }
}

- (BOOL)decisionHandlerURL:(NSURL *)url {
  if (([url.scheme isEqualToString:@"https"] || [url.scheme isEqualToString:@"http"]) && [url.host isEqualToString:@"itunes.apple.com"]) {
    NSString *newURLString = [url.absoluteString stringByReplacingOccurrencesOfString:url.scheme withString:@"itms-appss"];
    NSURL *newURL = [NSURL URLWithString:newURLString];
    if ([[UIApplication sharedApplication] respondsToSelector:@selector(openURL:options:completionHandler:)]) {
      [[UIApplication sharedApplication] openURL:newURL options:@{} completionHandler:^(BOOL success) {
        if (success) {
          if (_onLoadingFinish) {
            _onLoadingFinish([self baseEvent]);
          }
          NSLog(@"Launching %@ was successfull", url);
        }
      }];
    } else {
      [[UIApplication sharedApplication] openURL:newURL];
    }
    return YES;
  }
  return NO;
}

- (void)webView:(__unused WKWebView *)webView didFailProvisionalNavigation:(__unused WKNavigation *)navigation withError:(NSError *)error
{
  if (_onLoadingError) {
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
      // NSURLErrorCancelled is reported when a page has a redirect OR if you load
      // a new URL in the WebView before the previous one came back. We can just
      // ignore these since they aren't real errors.
      // http://stackoverflow.com/questions/1024748/how-do-i-fix-nsurlerrordomain-error-999-in-iphone-3-0-os
      return;
    }
    
    //  In case of WKWebview can't handle a link(deep link), check if there is any application in iPhone can handle, then open link by that application. In addition, other deeplinks also handled automatic by iOS.
    NSURL *url = error.userInfo[NSURLErrorFailingURLErrorKey];
    BOOL shouldOpenDeeplink = !url || [url.scheme isEqualToString:@"https"] || [url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"ftp"];
    if (error.code == -1002 && error.userInfo[NSURLErrorFailingURLStringErrorKey] && !shouldOpenDeeplink) {
      if ([[UIApplication sharedApplication] respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
          if (success) {
            if (_onLoadingFinish) {
              _onLoadingFinish([self baseEvent]);
            }
          } else {
            [self sendError:error forURLString:error.userInfo[NSURLErrorFailingURLStringErrorKey]];
          }
        }];
      } else {
        [[UIApplication sharedApplication] openURL:url];
        if (_onLoadingFinish) {
          _onLoadingFinish([self baseEvent]);
        }
      }
    } else {
      [self sendError:error forURLString:error.userInfo[NSURLErrorFailingURLStringErrorKey]];
    }
  }
}

- (void)sendError:(NSError *)error forURLString:(NSString *)url {
  if (_onLoadingError) {
    isDisplayingError = YES;
    NSMutableDictionary<NSString *, id> *event = [self baseEvent];
    [event addEntriesFromDictionary:@{
                                      @"domain": error.domain,
                                      @"code": @(error.code),
                                      @"description": error.localizedDescription,
                                      }];
    NSDictionary *errorInfo = event.copy;
    [event setValue:errorInfo forKey:@"error"];
    [event setValue:url forKey:@"url"];
    _onLoadingError(event);
  }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(__unused WKNavigation *)navigation
{
  if (resourceBundle) {
    NSString *jsFile = @"_webview";
    
    NSString *jsFilePath = [resourceBundle pathForResource:jsFile ofType:@"js"];
    NSURL *jsURL = [NSURL fileURLWithPath:jsFilePath];
    NSString *javascriptCode = [NSString stringWithContentsOfFile:jsURL.path encoding:NSUTF8StringEncoding error:nil];
    [_webView stringByEvaluatingJavaScriptFromString:javascriptCode];
  }
  if (_injectedJavaScript != nil) {
    [webView evaluateJavaScript:_injectedJavaScript completionHandler:^(id result, NSError *error) {
      NSMutableDictionary<NSString *, id> *event = [self baseEvent];
      event[@"jsEvaluationValue"] = [NSString stringWithFormat:@"%@", result];
      _onLoadingFinish(event);
    }];
  }
  // we only need the final 'finishLoad' call so only fire the event when we're actually done loading.
  else if (_onLoadingFinish && !webView.loading && ![webView.URL.absoluteString isEqualToString:@"about:blank"]) {
    _onLoadingFinish([self baseEvent]);
  }
  
  [webView evaluateJavaScript:@"document.body.style.webkitTouchCallout='none';" completionHandler:nil];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
  decisionHandler(WKNavigationResponsePolicyAllow);
}

#pragma mark - WKUIDelegate

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
  UIAlertController *alertController = [UIAlertController alertControllerWithTitle:message message:nil preferredStyle:UIAlertControllerStyleAlert];
  
  [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
    completionHandler();
  }]];
  UIViewController *presentingController = RCTPresentedViewController();
  [presentingController presentViewController:alertController animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler {
  
  // TODO We have to think message to confirm "YES"
  UIAlertController *alertController = [UIAlertController alertControllerWithTitle:message message:nil preferredStyle:UIAlertControllerStyleAlert];
  [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    completionHandler(YES);
  }]];
  [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
    completionHandler(NO);
  }]];
  UIViewController *presentingController = RCTPresentedViewController();
  [presentingController presentViewController:alertController animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)defaultText initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSString *))completionHandler {
  
  UIAlertController *alertController = [UIAlertController alertControllerWithTitle:prompt message:nil preferredStyle:UIAlertControllerStyleAlert];
  [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
    textField.text = defaultText;
  }];
  
  [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    NSString *input = ((UITextField *)alertController.textFields.firstObject).text;
    completionHandler(input);
  }]];
  
  [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
    completionHandler(nil);
  }]];
  UIViewController *presentingController = RCTPresentedViewController();
  [presentingController presentViewController:alertController animated:YES completion:nil];
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures
{
  NSString *scheme = navigationAction.request.URL.scheme;
  if ((navigationAction.targetFrame.isMainFrame || _openNewWindowInWebView) && ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
    NSMutableDictionary<NSString *, id> *event = [self baseEvent];
    [event addEntriesFromDictionary: @{
                                       @"url": (navigationAction.request.URL).absoluteString,
                                       @"navigationType": @(navigationAction.navigationType)
                                       }];
    if (![self.delegate webView:self shouldCreateNewWindow:event withCallback:_onShouldCreateNewWindow]) {
      [webView loadRequest:navigationAction.request];
    }
  } else {
    UIApplication *app = [UIApplication sharedApplication];
    NSURL *url = navigationAction.request.URL;
    if ([app canOpenURL:url]) {
      [app openURL:url];
    }
  }
  return nil;
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView
{
  RCTLogWarn(@"Webview Process Terminated");
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
  if (_onNavigationResponse) {
    NSDictionary *headers = @{};
    NSInteger statusCode = 200;
    if([navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]]){
        headers = ((NSHTTPURLResponse *)navigationResponse.response).allHeaderFields;
        statusCode = ((NSHTTPURLResponse *)navigationResponse.response).statusCode;
    }

    NSMutableDictionary<NSString *, id> *event = [self baseEvent];
    [event addEntriesFromDictionary:@{
                                      @"headers": headers,
                                      @"status": [NSHTTPURLResponse localizedStringForStatusCode:statusCode],
                                      @"statusCode": @(statusCode),
                                      }];
    _onNavigationResponse(event);
  }

  decisionHandler(WKNavigationResponsePolicyAllow);
}

@end
