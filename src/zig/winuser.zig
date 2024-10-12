const std = @import("std");
const win: type = std.os.windows;

pub const UINT = win.UINT;
pub const INT = win.INT;
pub const DWORD = win.DWORD;
pub const LPVOID = win.LPVOID;
pub const HINSTANCE = win.HINSTANCE;
pub const HICON = win.HICON;
pub const HWND = win.HWND;
pub const HCURSOR = win.HCURSOR;
pub const HBRUSH = win.HBRUSH;
pub const HMENU = win.HMENU;
pub const LPCSTR = win.LPCSTR;
pub const ATOM = win.ATOM;
pub const HANDLE = win.HANDLE;
pub const POINT = win.POINT;

pub const LRESULT = win.LRESULT;
pub const WPARAM = win.WPARAM;
pub const LPARAM = win.LPARAM;
pub const HMODULE = win.HMODULE;


pub const WINAPI = win.WINAPI;


const WNDPROC = *const fn (hwnd: HWND, param1: UINT, param2: WPARAM, param3: LPARAM) LRESULT;


pub const WNDCLASSEXA = extern struct {
    cbSize: UINT,
    style: UINT,

    lpfnWndProc: WNDPROC,
    cbClsExtra: INT,
    cbWndExtra: INT,
    hInstance: HINSTANCE,
    hIcon: HICON,
    hCursor: HCURSOR,
    hbrBackground: HBRUSH,
    lpszMenuName: LPCSTR,
    lpszClassName: LPCSTR,
    hIconSm: HICON,
};


pub const MSG = extern struct {
	hwnd: HWND,
	message: UINT,
	wParam: WPARAM,
	lParam: LPARAM,
	time: DWORD,
	pt: POINT,
};


pub const CS_VREDRAW          = 0x0001;
pub const CS_HREDRAW          = 0x0002;
pub const CS_DBLCLKS          = 0x0008;
pub const CS_OWNDC            = 0x0020;
pub const CS_CLASSDC          = 0x0040;
pub const CS_PARENTDC         = 0x0080;
pub const CS_NOCLOSE          = 0x0200;
pub const CS_SAVEBITS         = 0x0800;
pub const CS_BYTEALIGNCLIENT  = 0x1000;
pub const CS_BYTEALIGNWINDOW  = 0x2000;
pub const CS_GLOBALCLASS      = 0x4000;


pub extern "user32" fn RegisterClassExA( wndClass: *const WNDCLASSEXA) callconv(WINAPI) ATOM;

pub extern "user32" fn CreateWindowExA( dwExStyle: DWORD, lpClassName: LPCSTR, lpWindowName: LPCSTR, dwStyle: DWORD, X: INT, Y: INT, nWidth: INT, nHeight: INT, hWndParent: HWND, hMenu: HMENU, hInstance: HINSTANCE, lpParam: LPVOID) callconv(WINAPI) HWND;

pub extern "user32" fn PeekMessageA( lpMsg: *MSG, hWnd: HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT, wRemoveMsg: UINT ) callconv(WINAPI) bool;


pub extern "user32" fn DefWindowProcA( hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(WINAPI) LRESULT;

pub extern "user32" fn GetModuleHandleA( lpModuleName: ?LPCSTR ) callconv(WINAPI) HMODULE;