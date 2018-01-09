package com.phoebe.pbwebview;

import com.facebook.react.module.annotations.ReactModule;
import com.facebook.react.uimanager.ThemedReactContext;

/**
 * Created by binhnguyen on 1/9/18.
 */
@ReactModule(name = PBNestedWebViewManager.REACT_CLASS)
public class PBNestedWebViewManager extends PBWebViewManager {
    static final String REACT_CLASS = "PBNestedWebView";

    @Override
    public String getName() {
        return REACT_CLASS;
    }

    @Override
    protected PBWebView createWebViewInstance(final ThemedReactContext reactContext) {
        return new NestedWebView(reactContext);
    }
}
