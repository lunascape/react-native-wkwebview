/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

package com.phoebe.pbwebview;

import javax.annotation.Nullable;

import java.io.File;
import java.io.FileOutputStream;
import java.io.UnsupportedEncodingException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.DialogInterface;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Picture;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Message;
import android.text.TextUtils;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewGroup.LayoutParams;
import android.webkit.ConsoleMessage;
import android.webkit.GeolocationPermissions;
import android.webkit.HttpAuthHandler;
import android.webkit.WebChromeClient;
import android.webkit.WebView;
import android.webkit.WebView.HitTestResult;
import android.webkit.WebViewClient;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebSettings;
import android.widget.Button;
import android.widget.EditText;
import android.widget.RelativeLayout;
import android.widget.TextView;

import com.facebook.common.logging.FLog;
import com.facebook.react.common.ReactConstants;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.LifecycleEventListener;
import com.facebook.react.bridge.ReactContext;
import com.facebook.react.bridge.ReadableArray;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.ReadableMapKeySetIterator;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.common.MapBuilder;
import com.facebook.react.common.build.ReactBuildConfig;
import com.facebook.react.module.annotations.ReactModule;
import com.facebook.react.uimanager.SimpleViewManager;
import com.facebook.react.uimanager.ThemedReactContext;
import com.facebook.react.uimanager.UIManagerModule;
import com.facebook.react.uimanager.annotations.ReactProp;
import com.facebook.react.uimanager.events.ContentSizeChangeEvent;
import com.facebook.react.uimanager.events.Event;
import com.facebook.react.uimanager.events.EventDispatcher;
import com.facebook.react.views.webview.events.TopLoadingErrorEvent;
import com.facebook.react.views.webview.events.TopLoadingFinishEvent;
import com.facebook.react.views.webview.events.TopLoadingStartEvent;
import com.facebook.react.views.webview.events.TopMessageEvent;
import com.phoebe.events.PBWebViewEvent;

import org.json.JSONObject;
import org.json.JSONException;

/**
 * Manages instances of {@link WebView}
 *
 * Can accept following commands:
 *  - GO_BACK
 *  - GO_FORWARD
 *  - RELOAD
 *
 * {@link WebView} instances could emit following direct events:
 *  - topLoadingFinish
 *  - topLoadingStart
 *  - topLoadingError
 *
 * Each event will carry the following properties:
 *  - target - view's react tag
 *  - url - url set for the webview
 *  - loading - whether webview is in a loading state
 *  - title - title of the current page
 *  - canGoBack - boolean, whether there is anything on a history stack to go back
 *  - canGoForward - boolean, whether it is possible to request GO_FORWARD command
 */
@ReactModule(name = PBWebViewManager.REACT_CLASS)
public class PBWebViewManager extends SimpleViewManager<WebView> {

  protected static final String REACT_CLASS = "PBWebView";

  private static final String HTML_ENCODING = "UTF-8";
  private static final String HTML_MIME_TYPE = "text/html; charset=utf-8";
  private static final String BRIDGE_NAME = "__REACT_WEB_VIEW_BRIDGE";

  private static final String HTTP_METHOD_POST = "POST";

  public static final int COMMAND_GO_BACK = 1;
  public static final int COMMAND_GO_FORWARD = 2;
  public static final int COMMAND_RELOAD = 3;
  public static final int COMMAND_STOP_LOADING = 4;
  public static final int COMMAND_POST_MESSAGE = 5;
  public static final int COMMAND_INJECT_JAVASCRIPT = 6;
  public static final int CAPTURE_SCREEN = 7;
  public static final int SET_GEOLOCATION_PERMISSION = 8;

  public static final String DOWNLOAD_DIRECTORY = Environment.getExternalStorageDirectory() + "/Android/data/jp.co.lunascape.android.ilunascape/downloads/";

  // Use `webView.loadUrl("about:blank")` to reliably reset the view
  // state and release page resources (including any running JavaScript).
  private static final String BLANK_URL = "about:blank";

  private WebViewConfig mWebViewConfig;
  private @Nullable WebView.PictureListener mPictureListener;

  protected static class ReactWebViewClient extends WebViewClient {

    private boolean mLastLoadFailed = false;

    @Override
    public void onPageFinished(WebView webView, String url) {
      super.onPageFinished(webView, url);

      if (!mLastLoadFailed) {
        PBWebView reactWebView = (PBWebView) webView;
        reactWebView.callInjectedJavaScript();
        reactWebView.linkBridge();
        emitFinishEvent(webView, url);
      }
    }

    @Override
    public void onPageStarted(WebView webView, String url, Bitmap favicon) {
      super.onPageStarted(webView, url, favicon);
      mLastLoadFailed = false;

      dispatchEvent(
          webView,
          new TopLoadingStartEvent(
              webView.getId(),
              createWebViewEvent(webView, url)));
    }

    @Override
    public boolean shouldOverrideUrlLoading(WebView view, String url) {
        if (url.startsWith("http://") || url.startsWith("https://") ||
            url.startsWith("file://")) {
          return false;
        } else {
          PBWebView webView = (PBWebView) view;
          ArrayList<Object> customSchemes = webView.getCustomSchemes();
          try {
            Uri uri = Uri.parse(url);
            // Checking supported scheme only
            if (customSchemes != null && customSchemes.contains(uri.getScheme())) {
              webView.shouldStartLoadWithRequest(url);
              return true;
            } else if (uri.getScheme().equalsIgnoreCase("intent")) {
              // Get payload and scheme the intent wants to open
              Pattern pattern = Pattern.compile("^intent://(\\S*)#Intent;.*scheme=([a-zA-Z]+)");
              Matcher matcher = pattern.matcher(url);
              if (matcher.find()) {
                String payload = matcher.group(1);
                String scheme = matcher.group(2);
                // Checking supported scheme only
                if (customSchemes != null && customSchemes.contains(scheme)) {
                  String convertedUrl = scheme + "://" + payload;
                  webView.shouldStartLoadWithRequest(convertedUrl);
                  return true;
                }
              }
            }
            Intent intent = new Intent(Intent.ACTION_VIEW, uri);
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            view.getContext().startActivity(intent);
          } catch (ActivityNotFoundException e) {
            FLog.w(ReactConstants.TAG, "activity not found to handle uri scheme for: " + url, e);
          }
          return true;
        }
    }

    @Override
    public void onReceivedError(
        WebView webView,
        int errorCode,
        String description,
        String failingUrl) {
      super.onReceivedError(webView, errorCode, description, failingUrl);
      mLastLoadFailed = true;

      // In case of an error JS side expect to get a finish event first, and then get an error event
      // Android WebView does it in the opposite way, so we need to simulate that behavior
      emitFinishEvent(webView, failingUrl);

      WritableMap eventData = createWebViewEvent(webView, failingUrl);
      eventData.putDouble("code", errorCode);
      eventData.putString("description", description);

      dispatchEvent(
          webView,
          new TopLoadingErrorEvent(webView.getId(), eventData));
    }

    @Override
    public void doUpdateVisitedHistory(WebView webView, String url, boolean isReload) {
      super.doUpdateVisitedHistory(webView, url, isReload);

      dispatchEvent(
          webView,
          new TopLoadingStartEvent(
              webView.getId(),
              createWebViewEvent(webView, url)));
    }

    private void emitFinishEvent(WebView webView, String url) {
      dispatchEvent(
          webView,
          new TopLoadingFinishEvent(
              webView.getId(),
              createWebViewEvent(webView, url)));
    }

    private WritableMap createWebViewEvent(WebView webView, String url) {
      WritableMap event = Arguments.createMap();
      event.putDouble("target", webView.getId());
      // Don't use webView.getUrl() here, the URL isn't updated to the new value yet in callbacks
      // like onPageFinished
      event.putString("url", url);
      event.putBoolean("loading", !mLastLoadFailed && webView.getProgress() != 100);
      event.putString("title", webView.getTitle());
      event.putBoolean("canGoBack", webView.canGoBack());
      event.putBoolean("canGoForward", webView.canGoForward());
      return event;
    }

    @Override
    public void onReceivedHttpAuthRequest(WebView view, final HttpAuthHandler handler, String host, String realm) {
      AlertDialog.Builder builder = new AlertDialog.Builder(view.getContext());
      LayoutInflater inflater = LayoutInflater.from(view.getContext());
      builder.setView(inflater.inflate(R.layout.authenticate, null));

      final AlertDialog alertDialog = builder.create();
      alertDialog.getWindow().setLayout(600, 400);
      alertDialog.show();
      TextView titleTv = (TextView) alertDialog.findViewById(R.id.tv_login);
      titleTv.setText(view.getResources().getString(R.string.login_title).replace("%s", host));
      Button btnLogin = (Button) alertDialog.findViewById(R.id.btn_login);
      Button btnCancel = (Button) alertDialog.findViewById(R.id.btn_cancel);
      final EditText userField = (EditText) alertDialog.findViewById(R.id.edt_username);
      final EditText passField = (EditText) alertDialog.findViewById(R.id.edt_password);
      btnCancel.setOnClickListener(new View.OnClickListener() {
        @Override
        public void onClick(View view) {
          alertDialog.dismiss();
          handler.cancel();
        }
      });
      btnLogin.setOnClickListener(new View.OnClickListener() {
        @Override
        public void onClick(View view) {
          alertDialog.dismiss();
          handler.proceed(userField.getText().toString(), passField.getText().toString());
        }
      });
    }

  }

  /**
   * Subclass of {@link WebView} that implements {@link LifecycleEventListener} interface in order
   * to call {@link WebView#destroy} on activty destroy event and also to clear the client
   */
  protected static class PBWebView extends WebView implements LifecycleEventListener {
    private @Nullable String injectedJS;
    private boolean messagingEnabled = false;
    private ArrayList<Object> customSchemes = new ArrayList<>();
    private GeolocationPermissions.Callback _callback;

    private class ReactWebViewBridge {
      PBWebView mContext;

      ReactWebViewBridge(PBWebView c) {
        mContext = c;
      }

      @JavascriptInterface
      public void postMessage(String message) {
        mContext.onMessage(message);
      }
    }

    /**
     * WebView must be created with an context of the current activity
     *
     * Activity Context is required for creation of dialogs internally by WebView
     * Reactive Native needed for access to ReactNative internal system functionality
     *
     */
    public PBWebView(ThemedReactContext reactContext) {
      super(reactContext);
    }

    @Override
    public void onHostResume() {
      // do nothing
    }

    @Override
    public void onHostPause() {
      // do nothing
    }

    @Override
    public void onHostDestroy() {
      cleanupCallbacksAndDestroy();
    }

    public void setInjectedJavaScript(@Nullable String js) {
      injectedJS = js;
    }

    public void setMessagingEnabled(boolean enabled) {
      if (messagingEnabled == enabled) {
        return;
      }

      messagingEnabled = enabled;
      if (enabled) {
        addJavascriptInterface(new ReactWebViewBridge(this), BRIDGE_NAME);
        linkBridge();
      } else {
        removeJavascriptInterface(BRIDGE_NAME);
      }
    }

    public void callInjectedJavaScript() {
      if (getSettings().getJavaScriptEnabled() &&
          injectedJS != null &&
          !TextUtils.isEmpty(injectedJS)) {
        loadUrl("javascript:(function() {\n" + injectedJS + ";\n})();");
      }
    }

    public void linkBridge() {
      if (messagingEnabled) {
        if (ReactBuildConfig.DEBUG && Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
          // See isNative in lodash
          String testPostMessageNative = "String(window.postMessage) === String(Object.hasOwnProperty).replace('hasOwnProperty', 'postMessage')";
          evaluateJavascript(testPostMessageNative, new ValueCallback<String>() {
            @Override
            public void onReceiveValue(String value) {
              if (value.equals("true")) {
                FLog.w(ReactConstants.TAG, "Setting onMessage on a WebView overrides existing values of window.postMessage, but a previous value was defined");
              }
            }
          });
        }

        loadUrl("javascript:(" +
          "window.originalPostMessage = window.postMessage," +
          "window.postMessage = function(data) {" +
            BRIDGE_NAME + ".postMessage(String(data));" +
          "}" +
        ")");
      }
    }

    public void onMessage(String message) {
      dispatchEvent(this, new TopMessageEvent(this.getId(), message));
    }

    public void setCustomSchemes(ArrayList<Object> schemes) {
      this.customSchemes = schemes;
    }

    public ArrayList<Object> getCustomSchemes() {
      return this.customSchemes;
    }

    private void cleanupCallbacksAndDestroy() {
      setWebViewClient(null);
      destroy();
    }

    public void shouldStartLoadWithRequest(String url) {
      // Sending event to JS side
      WritableMap event = Arguments.createMap();
      event.putDouble("target", this.getId());
      event.putString("url", url);
      event.putBoolean("loading", false);
      event.putString("title", this.getTitle());
      event.putBoolean("canGoBack", this.canGoBack());
      event.putBoolean("canGoForward", this.canGoForward());
      dispatchEvent(this, PBWebViewEvent.createStartRequestEvent(this.getId(), event));
    }

    public void captureScreen(String message) {
      final String fileName = System.currentTimeMillis() + ".jpg";

      File d = new File(DOWNLOAD_DIRECTORY);
      d.mkdirs();
      final String localFilePath = DOWNLOAD_DIRECTORY + fileName;
      boolean success = false;
      try {
        Picture picture = this.capturePicture();
        int width = message.equals("CAPTURE_SCREEN") ? this.getWidth() : picture.getWidth();
        int height = message.equals("CAPTURE_SCREEN") ? this.getHeight() : picture.getHeight();
        Bitmap b = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(b);
        picture.draw(c);

        FileOutputStream fos = new FileOutputStream(localFilePath);
        if (fos != null) {
          b.compress(Bitmap.CompressFormat.JPEG, 80, fos);
          fos.close();
        }
        success = true;
      } catch (Throwable t) {
        System.out.println(t);
      } finally {
        WritableMap event = Arguments.createMap();
        event.putDouble("target", this.getId());
        event.putBoolean("result", success);
        if (success) {
          event.putString("data", localFilePath);
        }
        dispatchEvent(this, PBWebViewEvent.createCaptureScreenEvent(this.getId(), event));
      }
    }

    public void setGeolocationPermissionCallback(GeolocationPermissions.Callback callback) {
      this._callback = callback;
    }

    public void setGeolocationPermission(String origin, boolean allow) {
      if (this._callback != null) {
        this._callback.invoke(origin, allow, false);
        this.setGeolocationPermissionCallback(null);
      }
    }
  }

  public PBWebViewManager() {
    mWebViewConfig = new WebViewConfig() {
      public void configWebView(WebView webView) {
      }
    };
  }

  public PBWebViewManager(WebViewConfig webViewConfig) {
    mWebViewConfig = webViewConfig;
  }

  @Override
  public String getName() {
    return REACT_CLASS;
  }

  @Override
  protected WebView createViewInstance(final ThemedReactContext reactContext) {
    if(Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
      WebView.enableSlowWholeDocumentDraw();
    }
    final PBWebView webView = new PBWebView(reactContext);
    webView.setWebChromeClient(new WebChromeClient() {
      @Override
      public boolean onConsoleMessage(ConsoleMessage message) {
        if (ReactBuildConfig.DEBUG) {
          return super.onConsoleMessage(message);
        }
        // Ignore console logs in non debug builds.
        return true;
      }

      @Override
      public void onGeolocationPermissionsShowPrompt(final String origin, final GeolocationPermissions.Callback callback) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
          final boolean remember = false;
          AlertDialog.Builder builder = new AlertDialog.Builder(webView.getContext());
          builder.setTitle(webView.getContext().getResources().getString(R.string.locations));
          builder.setMessage(webView.getContext().getResources().getString(R.string.locations_ask_permission))
                  .setCancelable(true).setPositiveButton(webView.getContext().getResources().getString(R.string.allow), new DialogInterface.OnClickListener() {
            public void onClick(DialogInterface dialog, int id) {
              // origin, allow, remember
              callback.invoke(origin, true, remember);
            }
          }).setNegativeButton(webView.getContext().getResources().getString(R.string.dont_allow), new DialogInterface.OnClickListener() {
            public void onClick(DialogInterface dialog, int id) {
              // origin, allow, remember
              callback.invoke(origin, false, remember);
            }
          });
          AlertDialog alert = builder.create();
          alert.show();
        } else {
          webView.setGeolocationPermissionCallback(callback);
          WritableMap event = Arguments.createMap();
          event.putDouble("target", webView.getId());
          event.putString("origin", origin);
          dispatchEvent(webView, PBWebViewEvent.createLocationAskPermissionEvent(webView.getId(), event));
        }
      }
      @Override
      public boolean onCreateWindow(final WebView webView, boolean isDialog, boolean isUserGesture, Message resultMsg) {
        final WebView newView = new WebView(reactContext);
        newView.setWebViewClient(new WebViewClient() {
          @Override
          public void onPageStarted(WebView view, String url, Bitmap favicon) {
            WritableMap event = Arguments.createMap();
            event.putDouble("target", webView.getId());
            event.putString("url", url);
            event.putBoolean("loading", false);
            event.putString("title", webView.getTitle());
            event.putBoolean("canGoBack", webView.canGoBack());
            event.putBoolean("canGoForward", webView.canGoForward());
            dispatchEvent(webView, PBWebViewEvent.createNewWindowEvent(webView.getId(), event));
            newView.destroy();
          }
        });
        // Create dynamically a new view
        newView.setLayoutParams(new RelativeLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        webView.addView(newView);

        WebView.WebViewTransport transport = (WebView.WebViewTransport) resultMsg.obj;
        transport.setWebView(newView);
        resultMsg.sendToTarget();
        return true;
      }
    });
    reactContext.addLifecycleEventListener(webView);
    mWebViewConfig.configWebView(webView);
    webView.getSettings().setBuiltInZoomControls(true);
    webView.getSettings().setDisplayZoomControls(false);
    webView.getSettings().setDomStorageEnabled(true);
    webView.getSettings().setSupportMultipleWindows(true);
    webView.getSettings().setJavaScriptCanOpenWindowsAutomatically(true);

    // Fixes broken full-screen modals/galleries due to body height being 0.
    webView.setLayoutParams(
            new LayoutParams(LayoutParams.MATCH_PARENT,
                LayoutParams.MATCH_PARENT));

    if (ReactBuildConfig.DEBUG && Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
      WebView.setWebContentsDebuggingEnabled(true);
    }

    webView.setOnLongClickListener(new View.OnLongClickListener() {
      @Override
      public boolean onLongClick(View view) {
        final PBWebView webView = (PBWebView) view;
        HitTestResult result = webView.getHitTestResult();
        final String extra = result.getExtra();
        final int type = result.getType();
        if (type == HitTestResult.SRC_IMAGE_ANCHOR_TYPE || type == HitTestResult.SRC_ANCHOR_TYPE || type == HitTestResult.IMAGE_TYPE) {
          Handler handler = new Handler(webView.getHandler().getLooper()) {
            @Override
            public void handleMessage(Message msg) {
              String url = (String) msg.getData().get("url");
              String image_url = extra;
              if (url == null) {
                super.handleMessage(msg);
              } else {
                if (type == HitTestResult.SRC_ANCHOR_TYPE) {
                  image_url = "";
                }
                WritableMap data = Arguments.createMap();
                data.putString("type", "contextmenu");
                data.putString("url", url);
                data.putString("image_url", image_url);
                dispatchEvent(webView, PBWebViewEvent.createMessageEvent(webView.getId(), data));
              }
            }
          };
          Message msg = handler.obtainMessage();
          webView.requestFocusNodeHref(msg);
        }
        return true;
      }
    });

    return webView;
  }

  @ReactProp(name = "javaScriptEnabled")
  public void setJavaScriptEnabled(WebView view, boolean enabled) {
    view.getSettings().setJavaScriptEnabled(enabled);
  }

  @ReactProp(name = "scalesPageToFit")
  public void setScalesPageToFit(WebView view, boolean enabled) {
    view.getSettings().setUseWideViewPort(!enabled);
  }

  @ReactProp(name = "domStorageEnabled")
  public void setDomStorageEnabled(WebView view, boolean enabled) {
    view.getSettings().setDomStorageEnabled(enabled);
  }

  @ReactProp(name = "userAgent")
  public void setUserAgent(WebView view, @Nullable String userAgent) {
    if (userAgent != null) {
      // TODO(8496850): Fix incorrect behavior when property is unset (uA == null)
      view.getSettings().setUserAgentString(userAgent);
    }
  }

  @ReactProp(name = "mediaPlaybackRequiresUserAction")
  public void setMediaPlaybackRequiresUserAction(WebView view, boolean requires) {
    view.getSettings().setMediaPlaybackRequiresUserGesture(requires);
  }

  @ReactProp(name = "allowUniversalAccessFromFileURLs")
  public void setAllowUniversalAccessFromFileURLs(WebView view, boolean allow) {
    view.getSettings().setAllowUniversalAccessFromFileURLs(allow);
  }

  @ReactProp(name = "injectedJavaScript")
  public void setInjectedJavaScript(WebView view, @Nullable String injectedJavaScript) {
    ((PBWebView) view).setInjectedJavaScript(injectedJavaScript);
  }

  @ReactProp(name = "messagingEnabled")
  public void setMessagingEnabled(WebView view, boolean enabled) {
    ((PBWebView) view).setMessagingEnabled(enabled);
  }

  @ReactProp(name = "source")
  public void setSource(WebView view, @Nullable ReadableMap source) {
    if (source != null) {
      if (source.hasKey("html")) {
        String html = source.getString("html");
        if (source.hasKey("baseUrl")) {
          view.loadDataWithBaseURL(
              source.getString("baseUrl"), html, HTML_MIME_TYPE, HTML_ENCODING, null);
        } else {
          view.loadData(html, HTML_MIME_TYPE, HTML_ENCODING);
        }
        return;
      }
      if (source.hasKey("uri")) {
        String url = source.getString("uri");
        String previousUrl = view.getUrl();
        if (previousUrl != null && previousUrl.equals(url)) {
          return;
        }
        if (source.hasKey("method")) {
          String method = source.getString("method");
          if (method.equals(HTTP_METHOD_POST)) {
            byte[] postData = null;
            if (source.hasKey("body")) {
              String body = source.getString("body");
              try {
                postData = body.getBytes("UTF-8");
              } catch (UnsupportedEncodingException e) {
                postData = body.getBytes();
              }
            }
            if (postData == null) {
              postData = new byte[0];
            }
            view.postUrl(url, postData);
            return;
          }
        }
        HashMap<String, String> headerMap = new HashMap<>();
        if (source.hasKey("headers")) {
          ReadableMap headers = source.getMap("headers");
          ReadableMapKeySetIterator iter = headers.keySetIterator();
          while (iter.hasNextKey()) {
            String key = iter.nextKey();
            if ("user-agent".equals(key.toLowerCase(Locale.ENGLISH))) {
              if (view.getSettings() != null) {
                view.getSettings().setUserAgentString(headers.getString(key));
              }
            } else {
              headerMap.put(key, headers.getString(key));
            }
          }
        }
        view.loadUrl(url, headerMap);
        return;
      }
    }
    view.loadUrl(BLANK_URL);
  }

  @ReactProp(name = "onContentSizeChange")
  public void setOnContentSizeChange(WebView view, boolean sendContentSizeChangeEvents) {
    if (sendContentSizeChangeEvents) {
      view.setPictureListener(getPictureListener());
    } else {
      view.setPictureListener(null);
    }
  }

  @ReactProp(name = "mixedContentMode")
  public void setMixedContentMode(WebView view, @Nullable String mixedContentMode) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
      if (mixedContentMode == null || "never".equals(mixedContentMode)) {
        view.getSettings().setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
      } else if ("always".equals(mixedContentMode)) {
        view.getSettings().setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
      } else if ("compatibility".equals(mixedContentMode)) {
        view.getSettings().setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);
      }
    }
  }

  @ReactProp(name = "customSchemes")
  public void setCustomSchemes(WebView view, ReadableArray schemes) {
    ((PBWebView)view).setCustomSchemes(schemes.toArrayList());
  }

  @Override
  protected void addEventEmitters(ThemedReactContext reactContext, WebView view) {
    // Do not register default touch emitter and let WebView implementation handle touches
    view.setWebViewClient(new ReactWebViewClient());
  }

  @Override
  public @Nullable Map<String, Integer> getCommandsMap() {
    Map<String, Integer> map = MapBuilder.of(
        "goBack", COMMAND_GO_BACK,
        "goForward", COMMAND_GO_FORWARD,
        "reload", COMMAND_RELOAD,
        "stopLoading", COMMAND_STOP_LOADING,
        "postMessage", COMMAND_POST_MESSAGE,
        "injectJavaScript", COMMAND_INJECT_JAVASCRIPT,
        "captureScreen", CAPTURE_SCREEN
    );
    map.put("setGeolocationPermission", SET_GEOLOCATION_PERMISSION);
    return map;
  }

  @Override
  public void receiveCommand(WebView root, int commandId, @Nullable ReadableArray args) {
    switch (commandId) {
      case COMMAND_GO_BACK:
        root.goBack();
        break;
      case COMMAND_GO_FORWARD:
        root.goForward();
        break;
      case COMMAND_RELOAD:
        root.reload();
        break;
      case COMMAND_STOP_LOADING:
        root.stopLoading();
        break;
      case COMMAND_POST_MESSAGE:
        try {
          JSONObject eventInitDict = new JSONObject();
          eventInitDict.put("data", args.getString(0));
          root.loadUrl("javascript:(function () {" +
            "var event;" +
            "var data = " + eventInitDict.toString() + ";" +
            "try {" +
              "event = new MessageEvent('message', data);" +
            "} catch (e) {" +

              "event = document.createEvent('MessageEvent');" +
              "event.initMessageEvent('message', true, true, data.data, data.origin, data.lastEventId, data.source);" +
            "}" +
            "document.dispatchEvent(event);" +
          "})();");
        } catch (JSONException e) {
          throw new RuntimeException(e);
        }
        break;
      case COMMAND_INJECT_JAVASCRIPT:
        root.loadUrl("javascript:" + args.getString(0));
        break;
      case CAPTURE_SCREEN:
        ((PBWebView) root).captureScreen(args.getString(0));
        break;
      case SET_GEOLOCATION_PERMISSION:
        if (args.size() == 2) {
          ((PBWebView) root).setGeolocationPermission(args.getString(0), args.getBoolean(1));
        }
        break;
    }
  }

  @Override
  public void onDropViewInstance(WebView webView) {
    super.onDropViewInstance(webView);
    ((ThemedReactContext) webView.getContext()).removeLifecycleEventListener((PBWebView) webView);
    ((PBWebView) webView).cleanupCallbacksAndDestroy();
  }

  private WebView.PictureListener getPictureListener() {
    if (mPictureListener == null) {
      mPictureListener = new WebView.PictureListener() {
        @Override
        public void onNewPicture(WebView webView, Picture picture) {
          dispatchEvent(
            webView,
            new ContentSizeChangeEvent(
              webView.getId(),
              webView.getWidth(),
              webView.getContentHeight()));
        }
      };
    }
    return mPictureListener;
  }

  private static void dispatchEvent(WebView webView, Event event) {
    ReactContext reactContext = (ReactContext) webView.getContext();
    EventDispatcher eventDispatcher =
      reactContext.getNativeModule(UIManagerModule.class).getEventDispatcher();
    eventDispatcher.dispatchEvent(event);
  }

  @Override
  public @Nullable Map getExportedCustomDirectEventTypeConstants() {
    return MapBuilder.of(
      PBWebViewEvent.CREATE_WINDOW_EVENT_NAME, MapBuilder.of("registrationName", "onShouldCreateNewWindow"),
      PBWebViewEvent.SHOULD_START_REQUEST_EVENT_NAME, MapBuilder.of("registrationName", "onShouldStartLoadWithRequest"),
      PBWebViewEvent.CAPTURE_SCREEN_EVENT_NAME, MapBuilder.of("registrationName", "onCaptureScreen"),
      PBWebViewEvent.ASK_LOCATION_PERMISSION_EVENT_NAME, MapBuilder.of("registrationName", "onLocationAskPermission"),
      PBWebViewEvent.ON_MESSAGE_EVENT_NAME, MapBuilder.of("registrationName", "onLsMessage")
    );
  }
}
