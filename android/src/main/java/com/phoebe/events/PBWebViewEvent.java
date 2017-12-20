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
import com.facebook.react.uimanager.events.Event;
import com.facebook.react.uimanager.events.RCTEventEmitter;

/**
 * Event emitted when there is an error in loading.
 */

public class PBWebViewEvent {
  public static final String CREATE_WINDOW_EVENT_NAME = "createWindow";
  public static final String CAPTURE_SCREEN_EVENT_NAME = "captureScreen";
  public static final String SHOULD_START_REQUEST_EVENT_NAME = "shouldStartRequest";
  public static final String ASK_LOCATION_PERMISSION_EVENT_NAME = "askLocationPermission";
  public static final String ON_MESSAGE_EVENT_NAME = "onLsMessage";

  public static PBWebViewGenericEvent createNewWindowEvent(int viewId, WritableMap eventData) {
    return new PBWebViewGenericEvent(viewId, CREATE_WINDOW_EVENT_NAME, eventData);
  }

  public static PBWebViewGenericEvent createCaptureScreenEvent(int viewId, WritableMap eventData) {
    return new PBWebViewGenericEvent(viewId, CAPTURE_SCREEN_EVENT_NAME, eventData);
  }

  public static PBWebViewGenericEvent createStartRequestEvent(int viewId, WritableMap eventData) {
    return new PBWebViewGenericEvent(viewId, SHOULD_START_REQUEST_EVENT_NAME, eventData);
  }

  public static PBWebViewGenericEvent createLocationAskPermissionEvent(int viewId, WritableMap eventData) {
    return new PBWebViewGenericEvent(viewId, ASK_LOCATION_PERMISSION_EVENT_NAME, eventData);
  }

  public static PBWebViewGenericEvent createMessageEvent(int viewId, WritableMap eventData) {
    return new PBWebViewGenericEvent(viewId, ON_MESSAGE_EVENT_NAME, eventData);
  }

  static class PBWebViewGenericEvent extends Event<PBWebViewGenericEvent> {
    public String eventName;
    private WritableMap mEventData;

    public PBWebViewGenericEvent(int viewId, String eventName, WritableMap eventData) {
      super(viewId);
      this.mEventData = eventData;
      this.eventName = eventName;
    }

    @Override
    public String getEventName() {
      return this.eventName;
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
