package com.example.my_zik

import com.ryanheise.audioservice.AudioServiceActivity

// Extends AudioServiceActivity (instead of FlutterActivity) so tapping the
// media notification brings this activity back to the foreground.
class MainActivity : AudioServiceActivity()
