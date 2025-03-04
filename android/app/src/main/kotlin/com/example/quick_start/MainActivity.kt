package com.example.quick_start  

import android.app.PictureInPictureParams  
import android.os.Build  
import android.os.Bundle  
import android.util.Log  
import android.util.Rational  
import io.flutter.embedding.android.FlutterActivity  
import io.flutter.embedding.engine.FlutterEngine  
import io.flutter.plugin.common.MethodChannel  

class MainActivity : FlutterActivity() {  

    companion object {  
        var instance: MainActivity? = null  
    }  

    // MethodChannel for Flutter-native communication  
    private val Channel = "pip_channel"  

    // Flag to track if the user is on the meeting screen  
    private var isInMeetingScreen: Boolean = false  

    override fun onCreate(savedInstanceState: Bundle?) {  
        super.onCreate(savedInstanceState)  
        instance = this  
    }  

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {  
        super.configureFlutterEngine(flutterEngine)  

        // Establish a MethodChannel for interaction with Flutter  
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, Channel)  
            .setMethodCallHandler { call, result ->  
                when (call.method) {  
                    "enterPiPMode" -> {  
                        // Enter PiP mode upon request from Flutter  
                        startPiPMode()  
                        result.success(null)  
                    }  
                    "setMeetingScreen" -> {  
                        // Update the meeting screen flag based on Flutter’s input  
                        isInMeetingScreen = call.arguments as Boolean  
                        result.success(null)  
                    }  
                    else -> result.notImplemented()  
                }  
            }  
    }  

    // Sends a message from Android to Flutter via MethodChannel  
    private fun sendMessageToFlutter(message: String) {  
        // Notify Flutter when PiP mode is activated  
        MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, Channel)  
            .invokeMethod("sendMessage", hashMapOf("message" to message))  
    }  

    // Handles system-triggered PiP requests  
    override fun onPictureInPictureRequested(): Boolean {  
        Log.d("MainActivity", "onPictureInPictureRequested: $isInMeetingScreen")  

        // If the user is on the meeting screen, activate PiP mode and notify Flutter  
        return if (isInMeetingScreen) {  
            startPiPMode()  
            sendMessageToFlutter("Done")  
            true  
        } else {  
            super.onPictureInPictureRequested()  
        }  
    }  

    // Initiates PiP mode  
    private fun startPiPMode() {  
        Log.d("MainActivity", "startPiPService")  

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {  
            // Ensure PiP mode is supported (Android 8.0+)  
            val paramsBuilder = PictureInPictureParams.Builder()  
                .setAspectRatio(Rational(16, 9)) // Define the PiP window aspect ratio  
            this.enterPictureInPictureMode(paramsBuilder.build()) // Activate PiP mode  
        }  
    }  
} 
