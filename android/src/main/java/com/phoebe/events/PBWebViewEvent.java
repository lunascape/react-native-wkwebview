/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

package com.phoebe.events;

import com.facebook.react.bridge.WritableMap;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.uimanager.events.Event;
import com.facebook.react.uimanager.events.RCTEventEmitter;

/**
 * Event emitted when there is an error in loading.
 */

public class PBWebViewEvent {
  public static PBWebViewCreateWindowEvent createNewWindowEvent(int viewId, WritableMap eventData) {
    return new PBWebViewCreateWindowEvent(viewId, eventData);
  }

  public static PBWebViewCaptureScreenEvent createCaptureScreenEvent(int viewId, WritableMap eventData) {
    return new PBWebViewCaptureScreenEvent(viewId, eventData);
  }

  public static PBWebViewStartRequestEvent createStartRequestEvent(int viewId, WritableMap eventData) {
    return new PBWebViewStartRequestEvent(viewId, eventData);
  }

  public static PBWebViewLocationAskPermissionEvent createLocationAskPermissionEvent(int viewId, WritableMap eventData) {
    return new PBWebViewLocationAskPermissionEvent(viewId, eventData);
  }

  static class PBWebViewCreateWindowEvent extends Event<PBWebViewCreateWindowEvent> {

    public static final String EVENT_NAME = "createWindow";
    private WritableMap mEventData;

    public PBWebViewCreateWindowEvent(int viewId, WritableMap eventData) {
      super(viewId);
      mEventData = eventData;
    }

    @Override
    public String getEventName() {
      return EVENT_NAME;
    }

    @Override
    public boolean canCoalesce() {
      return false;
    }

    @Override
    public short getCoalescingKey() {
      // All events for a given view can be coalesced.
      return 0;
    }

    @Override
    public void dispatch(RCTEventEmitter rctEventEmitter) {
      rctEventEmitter.receiveEvent(getViewTag(), getEventName(), mEventData);
    }
  }

  static class PBWebViewCaptureScreenEvent extends Event<PBWebViewCreateWindowEvent> {

    public static final String EVENT_NAME = "captureScreen";
    private WritableMap mEventData;

    public PBWebViewCaptureScreenEvent(int viewId, WritableMap eventData) {
      super(viewId);
      mEventData = eventData;
    }

    @Override
    public String getEventName() {
      return EVENT_NAME;
    }

    @Override
    public boolean canCoalesce() {
      return false;
    }

    @Override
    public short getCoalescingKey() {
      // All events for a given view can be coalesced.
      return 0;
    }

    @Override
    public void dispatch(RCTEventEmitter rctEventEmitter) {
      rctEventEmitter.receiveEvent(getViewTag(), getEventName(), mEventData);
    }
  }

  static class PBWebViewStartRequestEvent extends Event<PBWebViewStartRequestEvent> {

    public static final String EVENT_NAME = "shouldStartRequest";
    private WritableMap mEventData;

    public PBWebViewStartRequestEvent(int viewId, WritableMap eventData) {
      super(viewId);
      mEventData = eventData;
    }

    @Override
    public String getEventName() {
      return EVENT_NAME;
    }

    @Override
    public boolean canCoalesce() {
      return false;
    }

    @Override
    public short getCoalescingKey() {
      // All events for a given view can be coalesced.
      return 0;
    }

    @Override
    public void dispatch(RCTEventEmitter rctEventEmitter) {
      rctEventEmitter.receiveEvent(getViewTag(), getEventName(), mEventData);
    }
  }

  static class PBWebViewLocationAskPermissionEvent extends Event<PBWebViewStartRequestEvent> {

    public static final String EVENT_NAME = "askLocationPermission";
    private WritableMap mEventData;

    public PBWebViewLocationAskPermissionEvent(int viewId, WritableMap eventData) {
      super(viewId);
      mEventData = eventData;
    }

    @Override
    public String getEventName() {
      return EVENT_NAME;
    }

    @Override
    public boolean canCoalesce() {
      return false;
    }

    @Override
    public short getCoalescingKey() {
      // All events for a given view can be coalesced.
      return 0;
    }

    @Override
    public void dispatch(RCTEventEmitter rctEventEmitter) {
      rctEventEmitter.receiveEvent(getViewTag(), getEventName(), mEventData);
    }
  }
}
