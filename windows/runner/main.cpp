#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <string>
#include <windows.h>

#include "app_links/app_links_plugin_c_api.h"
#include "flutter_window.h"
#include "utils.h"

namespace {
constexpr wchar_t kWindowTitle[] = L"trans";
constexpr wchar_t kUrlScheme[] = L"io.supabase.trans";

std::wstring Quote(const std::wstring& value) {
  return L"\"" + value + L"\"";
}

void RegisterUrlSchemeHandler() {
  wchar_t executable_path[MAX_PATH];
  const DWORD path_length =
      GetModuleFileNameW(nullptr, executable_path, MAX_PATH);
  if (path_length == 0 || path_length == MAX_PATH) {
    return;
  }

  const std::wstring scheme_key =
      L"Software\\Classes\\" + std::wstring(kUrlScheme);
  HKEY scheme;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, scheme_key.c_str(), 0, nullptr, 0,
                      KEY_WRITE, nullptr, &scheme, nullptr) != ERROR_SUCCESS) {
    return;
  }

  const wchar_t description[] = L"URL:Trans Protocol";
  RegSetValueExW(scheme, nullptr, 0, REG_SZ,
                 reinterpret_cast<const BYTE*>(description),
                 sizeof(description));

  const wchar_t url_protocol[] = L"";
  RegSetValueExW(scheme, L"URL Protocol", 0, REG_SZ,
                 reinterpret_cast<const BYTE*>(url_protocol),
                 sizeof(url_protocol));
  RegCloseKey(scheme);

  const std::wstring command_key = scheme_key + L"\\shell\\open\\command";
  HKEY command;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, command_key.c_str(), 0, nullptr, 0,
                      KEY_WRITE, nullptr, &command, nullptr) !=
      ERROR_SUCCESS) {
    return;
  }

  const std::wstring command_value =
      Quote(executable_path) + L" " + Quote(L"%1");
  RegSetValueExW(command, nullptr, 0, REG_SZ,
                 reinterpret_cast<const BYTE*>(command_value.c_str()),
                 static_cast<DWORD>((command_value.size() + 1) *
                                    sizeof(wchar_t)));
  RegCloseKey(command);
}

bool SendAppLinkToRunningInstance() {
  HWND hwnd = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", kWindowTitle);
  if (!hwnd) {
    return false;
  }

  SendAppLink(hwnd);

  WINDOWPLACEMENT placement = {sizeof(WINDOWPLACEMENT)};
  GetWindowPlacement(hwnd, &placement);
  switch (placement.showCmd) {
    case SW_SHOWMAXIMIZED:
      ShowWindow(hwnd, SW_SHOWMAXIMIZED);
      break;
    case SW_SHOWMINIMIZED:
      ShowWindow(hwnd, SW_RESTORE);
      break;
    default:
      ShowWindow(hwnd, SW_NORMAL);
      break;
  }
  SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0,
               SWP_SHOWWINDOW | SWP_NOSIZE | SWP_NOMOVE);
  SetForegroundWindow(hwnd);
  return true;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (SendAppLinkToRunningInstance()) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  RegisterUrlSchemeHandler();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
