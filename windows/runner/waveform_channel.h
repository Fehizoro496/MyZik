#ifndef RUNNER_WAVEFORM_CHANNEL_H_
#define RUNNER_WAVEFORM_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// Serves the "my_zik/waveform" method channel: "peaks" decodes an audio file
// with Media Foundation and returns its loudness envelope (one peak per
// bucket, 0 to 1) as a Float32List, for the lyrics editor's timeline.
//
// Decoding runs on a worker thread; its result is posted back to |window| and
// delivered from HandleMessage, on the platform thread, as Flutter requires.
class WaveformChannel {
 public:
  WaveformChannel(flutter::BinaryMessenger* messenger, HWND window);
  ~WaveformChannel();

  // Delivers a finished decode. Returns true when |message| was one.
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND window_;
};

#endif  // RUNNER_WAVEFORM_CHANNEL_H_
