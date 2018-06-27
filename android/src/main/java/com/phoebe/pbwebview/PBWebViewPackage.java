// Adapted from
// https://github.com/gijoehosaphat/react-native-keep-screen-on

package com.phoebe.pbwebview;

import com.facebook.react.ReactPackage;
import com.facebook.react.bridge.JavaScriptModule;
import com.facebook.react.bridge.NativeModule;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.uimanager.ViewManager;

import java.util.*;

public class PBWebViewPackage implements ReactPackage {
    private PBWebViewManager manager;
    private PBWebViewModule module;

    @Override
    public List<NativeModule> createNativeModules(ReactApplicationContext reactContext) {
        List<NativeModule> modules = new ArrayList<>();
        module = new PBWebViewModule(reactContext);
        module.setPackage(this);
        modules.add(module);
        return modules;
    }

    // Deprecated RN 0.47
    public List<Class<? extends JavaScriptModule>> createJSModules() {
        return Collections.emptyList();
    }

    @Override
    public List<ViewManager> createViewManagers(
                              ReactApplicationContext reactContext) {
        manager = new PBWebViewManager();
        manager.setPackage(this);
      return Arrays.<ViewManager>asList(
        manager
      );
    }

    public PBWebViewManager getManager(){
        return manager;
    }

    public PBWebViewModule getModule(){
        return module;
    }
}
