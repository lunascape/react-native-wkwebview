//
//  WKWebView+BrowsingHack.h
//  RCTWKWebView
//
//  Created by Tran Hong Nhi on 10/2/17.
//

#import <WebKit/WebKit.h>

@interface WKWebView (BrowserHack)

-(NSDictionary*)respondToTapAndHoldAtLocation:(CGPoint)location;
- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script;

@end
