# WebRTC JNI and reflection keep rules
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# HiveMQ MQTT Client, Netty, Dagger & JCTools rules
-keep class com.hivemq.client.** { *; }
-keep class io.netty.** { *; }
-dontwarn com.hivemq.client.**
-dontwarn io.netty.**
-dontwarn org.jctools.**
-dontwarn javax.annotation.**
-dontwarn org.slf4j.**

# CameraX & Extensions rules
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

# Keep CamMonitor data models
-keep class com.a0soft.gphone.camonitor.data.model.** { *; }
