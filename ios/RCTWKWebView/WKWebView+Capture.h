//
//  WKWebView+Capture.h
//  RCTWKWebView
//
//  Created by Tran Hong Nhi on 11/3/17.
//

#import <WebKit/WebKit.h>

@interface WKWebView (Capture)

- (void)contentScrollCapture:(void(^)(UIImage *))completionHandler;
- (void)contentFrameCapture:(void(^)(UIImage *))completionHandler;

@end
