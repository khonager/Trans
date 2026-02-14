# Suppress warnings for okhttp3 classes used by ucrop
# These classes are only used for downloading images from URLs, 
# which is generally not used in this app's cropping workflow.
-dontwarn okhttp3.Call
-dontwarn okhttp3.Dispatcher
-dontwarn okhttp3.OkHttpClient
-dontwarn okhttp3.Request$Builder
-dontwarn okhttp3.Request
-dontwarn okhttp3.Response
-dontwarn okhttp3.ResponseBody

# Keep Google ML Kit barcode scanning classes (stripped by R8 in release builds)
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_barcode_scanning.** { *; }
