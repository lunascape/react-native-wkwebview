#import "RCTWKWebView.h"

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
@interface _SwizzleHelper : NSObject @end
@implementation _SwizzleHelper
-(id)inputAccessoryView
{
  return nil;
}
@end

@interface RCTWKWebView () <WKNavigationDelegate, RCTAutoInsetsProtocol, WKScriptMessageHandler, WKUIDelegate, UIGestureRecognizerDelegate, WKScriptMessageHandler, UIScrollViewDelegate>

@property (nonatomic, copy) RCTDirectEventBlock onLoadingStart;
@property (nonatomic, copy) RCTDirectEventBlock onLoadingFinish;
@property (nonatomic, copy) RCTDirectEventBlock onLoadingError;
@property (nonatomic, copy) RCTDirectEventBlock onShouldStartLoadWithRequest;
@property (nonatomic, copy) RCTDirectEventBlock onShouldCreateNewWindow;
@property (nonatomic, copy) RCTDirectEventBlock onProgress;
@property (nonatomic, copy) RCTDirectEventBlock onMessage;
@property (assign) BOOL sendCookies;

@end

@implementation RCTWKWebView
{
  WKWebView *_webView;
  NSString *_injectedJavaScript;
  BOOL longPress;
  NSBundle* resourceBundle;
  CGPoint lastOffset;
  BOOL decelerating;
  BOOL dragging;
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
    
    NSString* bundlePath = [[NSBundle mainBundle] pathForResource:@"Scripts" ofType:@"bundle"];
    resourceBundle = [NSBundle bundleWithPath:bundlePath];
    
    _automaticallyAdjustContentInsets = YES;
    _contentInset = UIEdgeInsetsZero;
    
    WKWebViewConfiguration* config = [[WKWebViewConfiguration alloc] init];
    config.processPool = processPool;
    WKUserContentController* userController = [[WKUserContentController alloc]init];
    [userController addScriptMessageHandler:[[WeakScriptMessageDelegate alloc] initWithDelegate:self] name:@"reactNative"];
    config.userContentController = userController;
    _webView = [[WKWebView alloc] initWithFrame:self.bounds configuration:config];
    _webView.UIDelegate = self;
    _webView.scrollView.delegate = self;
    _webView.navigationDelegate = self;
    if ([_webView respondsToSelector:@selector(setAllowsLinkPreview:)]) {
      [_webView setAllowsLinkPreview:NO];
    }
    _webView.scrollView.decelerationRate = UIScrollViewDecelerationRateNormal;
    lastOffset = _webView.scrollView.contentOffset;
    [_webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
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
  // Avoid scrollDidScroll get called
  _webView.scrollView.delegate = nil;
  _webView.scrollView.contentOffset = CGPointMake(0, _webView.scrollView.contentOffset.y + adjustOffset.y);
  _webView.scrollView.delegate = self;
  
  // Notify to JS side new offset
  lastOffset = _webView.scrollView.contentOffset;
  NSDictionary *event = [self onScrollEvent:lastOffset moveDistance:CGPointMake(0, 0)];
  _onMessage(@{@"name":@"reactNative", @"body": @{@"type":@"onScrollEndDrag", @"data":event}});
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
  
  NSString* name = [NSString stringWithFormat:@"%@_SwizzleHelper", subview.class.superclass];
  Class newClass = NSClassFromString(name);
  
  if(newClass == nil)
  {
    newClass = objc_allocateClassPair(subview.class, [name cStringUsingEncoding:NSASCIIStringEncoding], 0);
    if(!newClass) return;
    
    Method method = class_getInstanceMethod([_SwizzleHelper class], @selector(inputAccessoryView));
    class_addMethod(newClass, @selector(inputAccessoryView), method_getImplementation(method), method_getTypeEncoding(method));
    
    objc_registerClassPair(newClass);
  }
  
  object_setClass(subview, newClass);
}


- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
  if (_onMessage) {
    _onMessage(@{@"name":message.name, @"body": message.body});
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

- (void)goBack
{
  [_webView goBack];
}

- (void)reload
{
  NSURLRequest *request = [RCTConvert NSURLRequest:self.source];
  if (request.URL && !_webView.URL.absoluteString.length) {
    [self loadRequest:request];
  }
  else {
    [_webView reload];
  }
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
    } else if (file) {
      NSURL *tempURL = [self fileURLForBuggyWKWebview8:[RCTConvert NSURL:file]];
      [_webView loadRequest:[NSURLRequest requestWithURL:tempURL]];
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
    // The page will load again when it comeback from error page.
    if ([request.URL isEqual:_webView.URL] && !isDisplayingError) {
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

- (NSURL *)fileURLForBuggyWKWebview8:(NSURL *)fileURL {
  if (!fileURL.isFileURL) {
    return fileURL;
  }
  NSError *error = nil;
  [fileURL checkResourceIsReachableAndReturnError:&error];
  if (error) {
    return nil;
  }
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSURL *tempDir = [[[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"www"] URLByAppendingPathComponent:@"files"];
  [fileManager createDirectoryAtURL:tempDir withIntermediateDirectories:YES attributes:nil error:nil];
  NSURL *destURL = [tempDir URLByAppendingPathComponent:fileURL.lastPathComponent];
  [fileManager removeItemAtURL:destURL error:nil];
  [fileManager copyItemAtURL:fileURL toURL:destURL error:&error];
  if (!error) {
    return destURL;
  }
  return nil;
}

- (void)findInPage:(NSString *)searchString completed:(RCTResponseSenderBlock)callback {
  if (searchString && searchString.length > 0) {
    [_webView removeAllHighlights];
    NSInteger results = [_webView highlightAllOccurencesOfString:searchString];
    [_webView scrollToHighlightTop];
    callback(@[@(results)]);
  }
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
  }
}

- (void)dealloc
{
  @try {
    [_webView removeObserver:self forKeyPath:@"estimatedProgress"];
    _webView.UIDelegate = nil;
    _webView.scrollView.delegate = nil;
    _webView.navigationDelegate = nil;
  }
  @catch (NSException * __unused exception) {}
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

#pragma mark - WKNavigationDelegate methods

- (void)webView:(__unused WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
  NSURLRequest *request = navigationAction.request;
  NSURL* url = request.URL;
  NSString* scheme = url.scheme;
  
  BOOL isJSNavigation = [scheme isEqualToString:RCTJSNavigationScheme];
  
  if (longPress) {
    longPress = NO;
    return decisionHandler(WKNavigationActionPolicyCancel);
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

- (void)webView:(__unused WKWebView *)webView didFailProvisionalNavigation:(__unused WKNavigation *)navigation withError:(NSError *)error
{
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
    [self sendError:error forURLString:error.userInfo[NSURLErrorFailingURLStringErrorKey]];
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
  NSString *jsFile = @"_webview";
  
  NSString *jsFilePath = [resourceBundle pathForResource:jsFile ofType:@"js"];
  NSURL *jsURL = [NSURL fileURLWithPath:jsFilePath];
  NSString *javascriptCode = [NSString stringWithContentsOfFile:jsURL.path encoding:NSUTF8StringEncoding error:nil];
  [_webView stringByEvaluatingJavaScriptFromString:javascriptCode];
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
}

- (NSDictionary*)onScrollEvent:(CGPoint)currentOffset moveDistance:(CGPoint)distance {
  UIScrollView* scrollView = _webView.scrollView;
  CGSize frameSize = scrollView.frame.size;
  
  NSMutableDictionary<NSString *, id> *event = [self baseEvent];
  [event addEntriesFromDictionary:@{@"contentOffset": @{@"x": @(currentOffset.x),@"y": @(currentOffset.y)}}];
  [event addEntriesFromDictionary:@{@"scroll": @{@"decelerating":@(decelerating), @"width": @(frameSize.width), @"height": @(frameSize.height)}}];
  [event addEntriesFromDictionary:@{@"contentSize": @{@"width" : @(scrollView.contentSize.width), @"height": @(scrollView.contentSize.height)}}];
  
  [event addEntriesFromDictionary:@{@"offset": @{@"dx": @(distance.x),@"dy": @(distance.y)}}];
  return event;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
  if (!decelerating && !dragging) {
    return;
  }
  
  CGPoint offset = scrollView.contentOffset;
  CGFloat dy = offset.y - lastOffset.y;
  CGSize frameSize = scrollView.frame.size;
  
  CGFloat offsetMin = 0;
  CGFloat offsetMax = scrollView.contentSize.height - frameSize.height;
  
  BOOL shouldLock = !decelerating && (_lockScroll == LockDirectionBoth || (dy < 0 && _lockScroll == LockDirectionUp && lastOffset.y == offsetMin) || (dy > 0 && _lockScroll == LockDirectionDown && lastOffset.y >= offsetMin));
  
  if (shouldLock) {
    CGRect scrollBounds = scrollView.bounds;
    scrollBounds.origin = lastOffset;
    scrollView.bounds = scrollBounds;
  } else {
    lastOffset = offset;
    if ((!decelerating && ((dy < 0 && _lockScroll == LockDirectionUp && offset.y >= offsetMin) || (dy > 0 && _lockScroll == LockDirectionDown && offset.y <= offsetMin))) ||
        (decelerating && (offset.y <= offsetMin || offset.y >= offsetMax))) {
      dy = 0;
    }
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
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
  decelerating = NO;
  dragging = YES;
  
  NSDictionary *event = [self onScrollEvent:scrollView.contentOffset moveDistance:CGPointMake(0, 0)];
  _onMessage(@{@"name":@"reactNative", @"body": @{@"type":@"onScrollBeginDrag", @"data":event}});
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

#pragma mark - Custom methods for custom context menu

@end


