package com.example.metmusic

// audio_service requires the host activity to be an AudioServiceActivity so it
// can attach the media session to the activity lifecycle. A plain FlutterActivity
// leaves the notification without playback controls.
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity()