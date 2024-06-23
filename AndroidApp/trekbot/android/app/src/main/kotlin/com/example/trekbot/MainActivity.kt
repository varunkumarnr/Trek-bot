package com.example.trekbot

import android.content.Context
import android.os.Bundle
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfRect
import org.opencv.core.Rect
import org.opencv.core.Scalar
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc
import org.opencv.objdetect.CascadeClassifier
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

class MainActivity : FlutterActivity() {

    private var cascadeClassifier: CascadeClassifier? = null
    private lateinit var methodChannel: MethodChannel

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize MethodChannel
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "face_detection_plugin")

        // Set MethodCallHandler
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "detectFaces" -> {
                    val imageBytes = call.arguments as ByteArray
                    val detected = detectFaces(imageBytes)
                    result.success(detected)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        OpenCVLoader.initDebug()
        loadCascadeClassifier()
    }

    private fun loadCascadeClassifier() {
        try {
            // Access resources after onCreate to ensure context is initialized
            val inputStream = resources.openRawResource(R.raw.haarcascade_frontalface_default)
            val cascadeDir = getDir("cascade", Context.MODE_PRIVATE)
            val cascadeFile = File(cascadeDir, "haarcascade_frontalface_default.xml")
            val outputStream = FileOutputStream(cascadeFile)

            val buffer = ByteArray(4096)
            var bytesRead: Int
            while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                outputStream.write(buffer, 0, bytesRead)
            }
            inputStream.close()
            outputStream.close()

            cascadeClassifier = CascadeClassifier(cascadeFile.absolutePath)
        } catch (e: IOException) {
            e.printStackTrace()
        }
    }

    private fun detectFaces(imageBytes: ByteArray): Boolean {
        if (cascadeClassifier == null) {
            Log.e("MainActivity", "CascadeClassifier is not initialized.")
            return false
        }

        // Implement your face detection logic here
        // This is just a placeholder
        return true
    }
}