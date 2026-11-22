#include "win32_window.h"

#include <algorithm>

#include <dwmapi.h>
#include <flutter_windows.h>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// نوار عنوان و دکمه‌های بستن/کوچک‌کردن. بدون لبهٔ تغییر اندازه و بدون Maximize.
constexpr DWORD kPhoneWindowStyle =
    WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPCHILDREN;

struct PhoneFrame {
  int x;
  int y;
  int width;
  int height;
};

// |logical_w| و |logical_h| اندازهٔ محتوای اپ به پیکسل منطقی (صفحهٔ گوشی) هستند.
// قاب بیرونی با DPI مانیتور ساخته می‌شود، وسط ناحیهٔ کاری قرار می‌گیرد و اگر
// از صفحه بزرگ‌تر باشد هم‌نسبت کوچک می‌شود.
PhoneFrame FrameForClient(unsigned int logical_w, unsigned int logical_h,
                          HMONITOR monitor, UINT dpi) {
  const double scale = dpi / 96.0;
  int client_w = std::max(1, Scale(static_cast<int>(logical_w), scale));
  int client_h = std::max(1, Scale(static_cast<int>(logical_h), scale));

  MONITORINFO info;
  info.cbSize = sizeof(info);
  if (monitor == nullptr || !GetMonitorInfo(monitor, &info)) {
    info.rcWork = RECT{0, 0, client_w, client_h};
  }

  auto outer_for = [&](int cw, int ch) {
    RECT frame{0, 0, cw, ch};
    if (!AdjustWindowRectExForDpi(&frame, kPhoneWindowStyle, FALSE, 0, dpi)) {
      AdjustWindowRectEx(&frame, kPhoneWindowStyle, FALSE, 0);
    }
    return frame;
  };

  RECT frame = outer_for(client_w, client_h);
  int outer_w = frame.right - frame.left;
  int outer_h = frame.bottom - frame.top;
  const int work_w = info.rcWork.right - info.rcWork.left;
  const int work_h = info.rcWork.bottom - info.rcWork.top;
  const int margin = Scale(16, scale);
  // عرض گوشی حفظ می‌شود. فقط بعدی که از صفحه بزرگ‌تر است کوتاه می‌شود
  // تا چیدمان مثل موبایل بماند و صفحه اسکرول شود.
  bool refit = false;
  if (outer_w > work_w - margin) {
    const int max_cw = std::max(1, work_w - margin - (outer_w - client_w));
    if (client_w > max_cw) {
      client_w = max_cw;
      refit = true;
    }
  }
  if (outer_h > work_h - margin) {
    const int max_ch = std::max(1, work_h - margin - (outer_h - client_h));
    if (client_h > max_ch) {
      client_h = max_ch;
      refit = true;
    }
  }
  if (refit) {
    frame = outer_for(client_w, client_h);
    outer_w = frame.right - frame.left;
    outer_h = frame.bottom - frame.top;
  }

  PhoneFrame result;
  result.width = outer_w;
  result.height = outer_h;
  result.x = info.rcWork.left + (work_w - outer_w) / 2;
  result.y = info.rcWork.top + (work_h - outer_h) / 2;
  return result;
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();
  (void)origin;

  client_width_ = size.width;
  client_height_ = size.height;

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {0, 0};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const PhoneFrame frame = FrameForClient(client_width_, client_height_, monitor, dpi);
  outer_width_ = frame.width;
  outer_height_ = frame.height;

  HWND window = CreateWindow(
      window_class, title.c_str(), kPhoneWindowStyle,
      frame.x, frame.y, frame.width, frame.height,
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      const UINT dpi = HIWORD(wparam);
      HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      const PhoneFrame frame =
          FrameForClient(client_width_, client_height_, monitor, dpi);
      outer_width_ = frame.width;
      outer_height_ = frame.height;
      SetWindowPos(hwnd, nullptr, frame.x, frame.y, frame.width, frame.height,
                   SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }
    case WM_GETMINMAXINFO: {
      if (outer_width_ > 0 && outer_height_ > 0) {
        auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
        info->ptMinTrackSize.x = outer_width_;
        info->ptMinTrackSize.y = outer_height_;
        info->ptMaxTrackSize.x = outer_width_;
        info->ptMaxTrackSize.y = outer_height_;
        info->ptMaxSize.x = outer_width_;
        info->ptMaxSize.y = outer_height_;
      }
      return 0;
    }
    case WM_SYSCOMMAND:
      switch (wparam & 0xFFF0) {
        case SC_MAXIMIZE:
        case SC_SIZE:
          return 0;
      }
      break;
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
