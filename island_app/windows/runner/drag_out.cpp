#include "drag_out.h"

#include <flutter/standard_method_codec.h>
#include <ole2.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <windows.h>

#include <string>
#include <vector>

namespace {

// BHID_DataObject {b8c0bd9f-ed24-455c-83e6-d5390c4fe8c4}
const GUID kDataObjectHandler = {
    0xb8c0bd9f, 0xed24, 0x455c,
    {0x83, 0xe6, 0xd5, 0x39, 0x0c, 0x4f, 0xe8, 0xc4}};

std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) {
    return std::wstring();
  }
  const int size = MultiByteToWideChar(
      CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring result(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                      result.data(), size);
  return result;
}

// Single item: bind to its parent folder so Explorer uses the file's own icon
// for the drag image.
IDataObject* CreateSingleFileDataObject(PIDLIST_ABSOLUTE pidl) {
  IShellFolder* folder = nullptr;
  PCUITEMID_CHILD child = nullptr;
  HRESULT hr = SHBindToParent(pidl, IID_PPV_ARGS(&folder), &child);
  if (FAILED(hr) || !folder) {
    return nullptr;
  }
  IDataObject* data = nullptr;
  hr = folder->GetUIObjectOf(nullptr, 1, &child, __uuidof(IDataObject), nullptr,
                             reinterpret_cast<void**>(&data));
  folder->Release();
  return SUCCEEDED(hr) ? data : nullptr;
}

// Multiple items: shell item array accepts absolute PIDLs from different
// folders and exposes a single CF_HDROP data object.
IDataObject* CreateMultiFileDataObject(
    const std::vector<PIDLIST_ABSOLUTE>& pidls) {
  std::vector<PCIDLIST_ABSOLUTE> items;
  items.reserve(pidls.size());
  for (PIDLIST_ABSOLUTE pidl : pidls) {
    items.push_back(pidl);
  }
  IShellItemArray* array = nullptr;
  HRESULT hr = SHCreateShellItemArrayFromIDLists(
      static_cast<UINT>(items.size()), items.data(), &array);
  if (FAILED(hr) || !array) {
    return nullptr;
  }
  IDataObject* data = nullptr;
  hr = array->BindToHandler(nullptr, kDataObjectHandler,
                            __uuidof(IDataObject),
                            reinterpret_cast<void**>(&data));
  array->Release();
  return SUCCEEDED(hr) ? data : nullptr;
}

// Only COPY is allowed; the original files are never moved.
bool StartFileDrag(const std::vector<std::wstring>& paths) {
  if (paths.empty()) {
    return false;
  }
  static const bool ole_ready = SUCCEEDED(OleInitialize(nullptr));
  if (!ole_ready) {
    return false;
  }

  std::vector<PIDLIST_ABSOLUTE> pidls;
  pidls.reserve(paths.size());
  for (const auto& path : paths) {
    PIDLIST_ABSOLUTE pidl = ILCreateFromPathW(path.c_str());
    if (pidl) {
      pidls.push_back(pidl);
    }
  }
  if (pidls.empty()) {
    return false;
  }

  IDataObject* data = pidls.size() == 1
                          ? CreateSingleFileDataObject(pidls.front())
                          : CreateMultiFileDataObject(pidls);
  for (PIDLIST_ABSOLUTE pidl : pidls) {
    ILFree(pidl);
  }
  if (!data) {
    return false;
  }

  DWORD effect = DROPEFFECT_COPY;
  HRESULT hr = SHDoDragDrop(nullptr, data, nullptr, DROPEFFECT_COPY, &effect);
  data->Release();
  return SUCCEEDED(hr);
}

}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateDragOutChannel(flutter::BinaryMessenger* messenger) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "gudong/drag", &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() != "startDrag") {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (!args) {
          result->Error("bad_args", "expected a map");
          return;
        }
        const flutter::EncodableValue key(std::string("paths"));
        const auto it = args->find(key);
        if (it == args->end()) {
          result->Error("bad_args", "missing paths");
          return;
        }
        const auto* raw_paths = std::get_if<flutter::EncodableList>(&it->second);
        if (!raw_paths || raw_paths->empty()) {
          result->Error("bad_args", "paths must not be empty");
          return;
        }
        std::vector<std::wstring> paths;
        paths.reserve(raw_paths->size());
        for (const auto& value : *raw_paths) {
          const auto* path = std::get_if<std::string>(&value);
          if (!path) {
            continue;
          }
          std::wstring wide = Utf8ToWide(*path);
          if (!wide.empty()) {
            paths.push_back(wide);
          }
        }
        if (paths.empty()) {
          result->Error("bad_args", "no valid paths");
          return;
        }
        const bool ok = StartFileDrag(paths);
        result->Success(flutter::EncodableValue(ok));
      });

  return channel;
}
