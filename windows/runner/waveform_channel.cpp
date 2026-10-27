#include "waveform_channel.h"

#include <flutter/standard_method_codec.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>

#include <algorithm>
#include <cmath>
#include <string>
#include <thread>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

// Posted to the window when a decode finishes; LPARAM owns a DecodeResult.
constexpr UINT kDecodeDoneMessage = WM_APP + 0x57;

using MethodResult = flutter::MethodResult<flutter::EncodableValue>;

struct DecodeResult {
  std::unique_ptr<MethodResult> result;
  std::vector<float> peaks;
  std::string error;
};

std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) return std::wstring();
  const int length = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                         static_cast<int>(text.size()),
                                         nullptr, 0);
  std::wstring wide(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      wide.data(), length);
  return wide;
}

// Decodes |path| to float PCM and keeps the loudest sample of each of
// |buckets| equal slices of the track, scaled so the loudest is 1. Returns an
// empty vector (and sets |error|) when the file can't be decoded.
std::vector<float> DecodePeaks(const std::wstring& path, int buckets,
                               std::string* error) {
  ComPtr<IMFSourceReader> reader;
  if (FAILED(MFCreateSourceReaderFromURL(path.c_str(), nullptr, &reader))) {
    *error = "Cannot open this file.";
    return {};
  }
  const DWORD audio = static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM);
  reader->SetStreamSelection(
      static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS), FALSE);
  reader->SetStreamSelection(audio, TRUE);

  ComPtr<IMFMediaType> wanted;
  MFCreateMediaType(&wanted);
  wanted->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
  wanted->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_Float);
  if (FAILED(reader->SetCurrentMediaType(audio, nullptr, wanted.Get()))) {
    *error = "Unsupported audio format.";
    return {};
  }
  ComPtr<IMFMediaType> actual;
  if (FAILED(reader->GetCurrentMediaType(audio, &actual))) {
    *error = "Unsupported audio format.";
    return {};
  }
  const UINT32 channels =
      std::max<UINT32>(1, MFGetAttributeUINT32(actual.Get(),
                                               MF_MT_AUDIO_NUM_CHANNELS, 1));
  const UINT32 rate =
      MFGetAttributeUINT32(actual.Get(), MF_MT_AUDIO_SAMPLES_PER_SECOND, 0);

  PROPVARIANT duration;
  PropVariantInit(&duration);
  LONGLONG hundred_ns = 0;
  if (SUCCEEDED(reader->GetPresentationAttribute(
          static_cast<DWORD>(MF_SOURCE_READER_MEDIASOURCE), MF_PD_DURATION,
          &duration))) {
    hundred_ns = static_cast<LONGLONG>(duration.uhVal.QuadPart);
  }
  PropVariantClear(&duration);
  if (rate == 0 || hundred_ns <= 0) {
    *error = "Unknown duration.";
    return {};
  }
  const double total_frames = hundred_ns / 1e7 * rate;
  const double frames_per_bucket = std::max(1.0, total_frames / buckets);

  std::vector<float> peaks(buckets, 0.0f);
  unsigned long long frame = 0;
  while (true) {
    DWORD flags = 0;
    ComPtr<IMFSample> sample;
    if (FAILED(reader->ReadSample(audio, 0, nullptr, &flags, nullptr,
                                  &sample))) {
      break;
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
    if (!sample) continue;
    ComPtr<IMFMediaBuffer> buffer;
    if (FAILED(sample->ConvertToContiguousBuffer(&buffer))) continue;
    BYTE* data = nullptr;
    DWORD length = 0;
    if (FAILED(buffer->Lock(&data, nullptr, &length))) continue;
    const float* samples = reinterpret_cast<const float*>(data);
    const size_t frames = length / sizeof(float) / channels;
    for (size_t f = 0; f < frames; ++f, ++frame) {
      float loudest = 0.0f;
      for (UINT32 c = 0; c < channels; ++c) {
        loudest = std::max(loudest, std::fabs(samples[f * channels + c]));
      }
      const int bucket = std::min(
          buckets - 1, static_cast<int>(frame / frames_per_bucket));
      peaks[bucket] = std::max(peaks[bucket], loudest);
    }
    buffer->Unlock();
  }

  const float loudest = *std::max_element(peaks.begin(), peaks.end());
  if (loudest > 0.0f) {
    for (float& peak : peaks) peak = std::min(1.0f, peak / loudest);
  }
  return peaks;
}

void DecodeOnWorker(HWND window, std::wstring path, int buckets,
                    std::unique_ptr<MethodResult> result) {
  std::thread([window, path = std::move(path), buckets,
               result = std::move(result)]() mutable {
    auto done = std::make_unique<DecodeResult>();
    done->result = std::move(result);
    const bool com = SUCCEEDED(CoInitializeEx(nullptr, COINIT_MULTITHREADED));
    if (SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) {
      done->peaks = DecodePeaks(path, buckets, &done->error);
      MFShutdown();
    } else {
      done->error = "Media Foundation is unavailable.";
    }
    if (com) CoUninitialize();
    if (PostMessage(window, kDecodeDoneMessage, 0,
                    reinterpret_cast<LPARAM>(done.get()))) {
      done.release();  // Owned by the message now.
    }
  }).detach();
}

}  // namespace

WaveformChannel::WaveformChannel(flutter::BinaryMessenger* messenger,
                                 HWND window)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "my_zik/waveform",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<MethodResult> result) {
        if (call.method_name() != "peaks") {
          result->NotImplemented();
          return;
        }
        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (!args) {
          result->Error("bad_args", "Expected a map.");
          return;
        }
        const auto path = args->find(flutter::EncodableValue("path"));
        const auto buckets = args->find(flutter::EncodableValue("buckets"));
        if (path == args->end() || buckets == args->end() ||
            !std::holds_alternative<std::string>(path->second) ||
            !std::holds_alternative<int32_t>(buckets->second)) {
          result->Error("bad_args", "Expected path and buckets.");
          return;
        }
        const int count = std::clamp(std::get<int32_t>(buckets->second), 1,
                                     100000);
        DecodeOnWorker(window_, Utf8ToWide(std::get<std::string>(path->second)),
                       count, std::move(result));
      });
}

WaveformChannel::~WaveformChannel() { channel_->SetMethodCallHandler(nullptr); }

bool WaveformChannel::HandleMessage(UINT message, WPARAM, LPARAM lparam) {
  if (message != kDecodeDoneMessage) return false;
  std::unique_ptr<DecodeResult> done(reinterpret_cast<DecodeResult*>(lparam));
  if (done->peaks.empty()) {
    done->result->Error("decode_failed", done->error);
  } else {
    done->result->Success(flutter::EncodableValue(std::move(done->peaks)));
  }
  return true;
}
