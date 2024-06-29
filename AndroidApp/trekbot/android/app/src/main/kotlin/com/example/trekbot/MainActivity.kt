package com.example.trekbot

import android.content.Context
import android.graphics.BitmapFactory
import android.os.Bundle
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfRect
import org.opencv.core.Rect
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.objdetect.CascadeClassifier
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

class MainActivity : FlutterActivity() {

    private var cascadeClassifier: CascadeClassifier? = null
    private lateinit var methodChannel: MethodChannel

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "face_detection_plugin")

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "detectFaces" -> {
                    val imageBytes = call.arguments as ByteArray
                    val detectedFaces = detectFaces(imageBytes)
                    result.success(detectedFaces)
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

    private fun detectFaces(imageBytes: ByteArray): List<Map<String, Int>> {
        if (cascadeClassifier == null) {
            Log.e("MainActivity", "CascadeClassifier is not initialized.")
            return emptyList()
        }
        val mat = decodeByteArrayToMat(imageBytes)
        if (mat.empty()) {
            Log.e("MainActivity", "Failed to decode byte array to Mat.")
            return emptyList()
        }
        val grayMat = Mat()
        Imgproc.cvtColor(mat, grayMat, Imgproc.COLOR_BGR2GRAY)


        val faces = MatOfRect()
        cascadeClassifier?.detectMultiScale(grayMat, faces, 1.1, 2, 2, Size(30.0, 30.0), Size())

        val faceList = mutableListOf<Map<String, Int>>()
        for (rect in faces.toArray()) {
            faceList.add(mapOf(
                "x" to rect.x,
                "y" to rect.y,
                "width" to rect.width,
                "height" to rect.height
            ))
        }

        Log.d("MainActivity", "Detected ${faceList.size} faces.")
        return faceList
    }
    private fun decodeByteArrayToMat(imageBytes: ByteArray): Mat {
        Log.d("MainActivity", "Decoding byte array to Mat, size: ${imageBytes.size}")
        val mat = Mat(1, imageBytes.size, CvType.CV_8U)
        mat.put(0, 0, imageBytes)

        val decodedMat = Imgcodecs.imdecode(mat, Imgcodecs.IMREAD_UNCHANGED)
        if (decodedMat.empty()) {
            Log.e("MainActivity", "Imgcodecs.imdecode returned an empty Mat.")
        } else {
            Log.d("MainActivity", "Imgcodecs.imdecode succeeded, Mat size: ${decodedMat.size()}")
        }
        return decodedMat
    }

}

