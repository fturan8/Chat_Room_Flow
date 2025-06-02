package com.example.chat_flow_new

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val RECORD_REQUEST_CODE = 101
    private val CHANNEL = "com.example.chat_flow_new/permissions"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        
        // Flutter ile iletişim kanalı oluştur
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermissions" -> {
                    setupPermissions { success ->
                        result.success(success)
                    }
                }
                "checkMicrophonePermission" -> {
                    val hasPermission = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                    result.success(hasPermission)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Android 10+ için screen-on flag
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        
        // Başlangıçta izinleri kontrol et
        setupPermissions()
    }
    
    private fun setupPermissions(callback: ((Boolean) -> Unit)? = null) {
        // Gerekli tüm izinleri tek seferde istiyoruz
        val permissions = mutableListOf(
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.INTERNET
        )
        
        // Android sürümüne göre depolama izinlerini ekle
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.S_V2) { // Android 12L ve öncesi
            permissions.add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            permissions.add(Manifest.permission.READ_EXTERNAL_STORAGE)
        } else { // Android 13+
            permissions.add(Manifest.permission.READ_MEDIA_AUDIO)
            permissions.add(Manifest.permission.READ_MEDIA_IMAGES)
        }
        
        // İzinleri kontrol et
        val permissionsToRequest = permissions.filter { 
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED 
        }.toTypedArray()
        
        // Eksik izinler varsa iste
        if (permissionsToRequest.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, permissionsToRequest, RECORD_REQUEST_CODE)
        } else {
            // Tüm izinler zaten verilmiş
            callback?.invoke(true)
        }
    }
    
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        when (requestCode) {
            RECORD_REQUEST_CODE -> {
                // İzin sonuçlarını logla
                var allGranted = true
                permissions.forEachIndexed { index, permission ->
                    val isGranted = grantResults.getOrNull(index) == PackageManager.PERMISSION_GRANTED
                    val result = if (isGranted) "GRANTED" else "DENIED"
                    println("İzin sonucu: $permission = $result")
                    
                    if (!isGranted) {
                        allGranted = false
                    }
                }
                
                // Flutter'a izin durumunu bildir
                val channel = flutterEngine?.dartExecutor?.binaryMessenger?.let {
                    MethodChannel(it, CHANNEL)
                }
                channel?.invokeMethod("permissionResult", allGranted)
            }
            else -> {
                super.onRequestPermissionsResult(requestCode, permissions, grantResults)
            }
        }
    }
}
