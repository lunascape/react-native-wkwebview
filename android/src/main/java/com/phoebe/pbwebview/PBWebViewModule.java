package com.phoebe.pbwebview;

import android.annotation.TargetApi;
import android.app.Activity;
import android.content.ClipData;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Parcelable;
import android.provider.MediaStore;
import android.support.annotation.VisibleForTesting;
import android.util.Log;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;

import com.facebook.react.bridge.ActivityEventListener;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;

import java.io.File;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.Date;

public class PBWebViewModule extends ReactContextBaseJavaModule implements ActivityEventListener {
    private ValueCallback<Uri> mUploadMessage;
    private ValueCallback<Uri[]> mUploadCallbackAboveL;
    private PBWebViewPackage mPackage;

    @VisibleForTesting
    public static final String REACT_CLASS = "AndroidWebViewModule";
    public static final int OPEN_PICKER_REQUEST_CODE = 123;
    private String mCameraPhotoPath;
    private Uri mCapturedImageURI = null;

    public PBWebViewModule(ReactApplicationContext context) {
        super(context);
        context.addActivityEventListener(this);
    }

    public PBWebViewPackage getPackage() {
        return this.mPackage;
    }

    public void setPackage(PBWebViewPackage _package) {
        this.mPackage = _package;
    }

    @Override
    public String getName() {
        return REACT_CLASS;
    }

    public Activity getActivity() {
        return getCurrentActivity();
    }

    public void setUploadMessage(ValueCallback<Uri> uploadMessage) {
        mUploadMessage = uploadMessage;
    }

    public void setmUploadCallbackAboveL(ValueCallback<Uri[]> mUploadCallbackAboveL) {
        this.mUploadCallbackAboveL = mUploadCallbackAboveL;
    }

    public void openFileChooserView(ValueCallback<Uri> uploadMessage, String acceptType) {
        mUploadMessage = uploadMessage;

        Activity activity = this.getActivity();
        File imageStorageDir = new File(
                Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_PICTURES)
                , "AndroidExampleFolder");
        if (!imageStorageDir.exists()) {
            // Create AndroidExampleFolder at sdcard
            imageStorageDir.mkdirs();
        }
        // Create camera captured image file path and name
        File file = new File(
                imageStorageDir + File.separator + "IMG_"
                        + String.valueOf(System.currentTimeMillis())
                        + ".jpg");
        mCapturedImageURI = Uri.fromFile(file);
        // Camera capture image intent
        final Intent captureIntent = new Intent(
                android.provider.MediaStore.ACTION_IMAGE_CAPTURE);
        captureIntent.putExtra(MediaStore.EXTRA_OUTPUT, mCapturedImageURI);
        Intent i = new Intent(Intent.ACTION_GET_CONTENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        i.setType("image/*");
        // Create file chooser intent
        Intent chooserIntent = Intent.createChooser(i, activity.getResources().getString(R.string.image_select));
        // Set camera intent to file chooser
        chooserIntent.putExtra(Intent.EXTRA_INITIAL_INTENTS
                , new Parcelable[] { captureIntent });
        // On select image call onActivityResult method of activity
        activity.startActivityForResult(chooserIntent, PBWebViewModule.OPEN_PICKER_REQUEST_CODE);
    }

    @TargetApi(21)
    public boolean openFileChooserViewL(ValueCallback<Uri[]> filePathCallback, WebChromeClient.FileChooserParams fileChooserParams) {
        // Double check that we don't have any existing callbacks
        if (mUploadCallbackAboveL != null) {
            mUploadCallbackAboveL.onReceiveValue(null);
        }
        mUploadCallbackAboveL = filePathCallback;

        Activity activity = this.getActivity();
        String[] types = fileChooserParams.getAcceptTypes();
        Intent takePictureIntent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
        if (takePictureIntent.resolveActivity(activity.getPackageManager()) != null) {
            // Create the File where the photo should go
            File photoFile = null;
            try {
                photoFile = createImageFile();
                takePictureIntent.putExtra("PhotoPath", mCameraPhotoPath);
            } catch (IOException ex) {
                // Error occurred while creating the File
                Log.e("customwebview", "Unable to create Image File", ex);
            }
            // Continue only if the File was successfully created
            if (photoFile != null) {
                mCameraPhotoPath = "file:" + photoFile.getAbsolutePath();
                takePictureIntent.putExtra(MediaStore.EXTRA_OUTPUT,
                        Uri.fromFile(photoFile));
            } else {
                takePictureIntent = null;
            }
        }
        Intent contentSelectionIntent = new Intent(Intent.ACTION_GET_CONTENT);
        contentSelectionIntent.addCategory(Intent.CATEGORY_OPENABLE);
        contentSelectionIntent.setType("image/*");
        Intent[] intentArray;
        if (takePictureIntent != null) {
            intentArray = new Intent[]{takePictureIntent};
        } else {
            intentArray = new Intent[0];
        }
        Intent chooserIntent = new Intent(Intent.ACTION_CHOOSER);
        chooserIntent.putExtra(Intent.EXTRA_INTENT, contentSelectionIntent);
        chooserIntent.putExtra(Intent.EXTRA_TITLE, activity.getResources().getString(R.string.image_select));
        chooserIntent.putExtra(Intent.EXTRA_INITIAL_INTENTS, intentArray);
        activity.startActivityForResult(chooserIntent, OPEN_PICKER_REQUEST_CODE);
        return true;
    }

    @Override
    public void onActivityResult(Activity activity, int requestCode, int resultCode, Intent data) {
        if (requestCode == OPEN_PICKER_REQUEST_CODE) {
            if (null == mUploadMessage && null == mUploadCallbackAboveL){
                return;
            }
            if (mUploadCallbackAboveL != null) {
                onActivityResultAboveL(requestCode, resultCode, data);
            } else if (mUploadMessage != null) {
                Uri result = resultCode != Activity.RESULT_OK ? null : data == null ? mCapturedImageURI : data.getData();
                mUploadMessage.onReceiveValue(result);
                mUploadMessage = null;
            }
        }
    }

    @TargetApi(Build.VERSION_CODES.LOLLIPOP)
    private void onActivityResultAboveL(int requestCode, int resultCode, Intent data) {
        if (requestCode != OPEN_PICKER_REQUEST_CODE || mUploadCallbackAboveL == null) {
            return;
        }
        Uri[] results = null;
        if (resultCode == Activity.RESULT_OK) {
            if (data != null) {
                String dataString = data.getDataString();
                ClipData clipData = data.getClipData();
                if (clipData != null) {
                    results = new Uri[clipData.getItemCount()];
                    for (int i = 0; i < clipData.getItemCount(); i++) {
                        ClipData.Item item = clipData.getItemAt(i);
                        results[i] = item.getUri();
                    }
                }
                if (dataString != null)
                    results = new Uri[]{Uri.parse(dataString)};
            } else if (mCameraPhotoPath != null) {
                results = new Uri[]{Uri.parse(mCameraPhotoPath)};
            }
        }
        mUploadCallbackAboveL.onReceiveValue(results);
        mUploadCallbackAboveL = null;
    }
    public void onNewIntent(Intent intent) {}

    private File createImageFile() throws IOException {
        // Create an image file name
        String timeStamp = new SimpleDateFormat("yyyyMMdd_HHmmss").format(new Date());
        String imageFileName = "JPEG_" + timeStamp + "_";
        File tempFile = File.createTempFile(imageFileName, ".jpg", getActivity().getCacheDir());
        tempFile.setWritable(true, false);
        return tempFile;
    }
}
