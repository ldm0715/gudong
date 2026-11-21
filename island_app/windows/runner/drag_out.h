#ifndef RUNNER_DRAG_OUT_H_
#define RUNNER_DRAG_OUT_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

// Starts a native Windows file drag on the platform thread.
// SHDoDragDrop enters a modal loop that pumps window messages, so it must be
// called from the UI thread.
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateDragOutChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_DRAG_OUT_H_
