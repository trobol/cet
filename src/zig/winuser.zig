const std = @import("std");
const win: type = std.os.windows;

pub const LONG = win.LONG;
pub const BOOL = win.BOOL;
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


const WNDPROC = *const fn (hwnd: HWND, param1: UINT, param2: WPARAM, param3: LPARAM) callconv(WINAPI) LRESULT;


pub const RECT = extern struct {
	left: LONG,
	top: LONG,
	right: LONG,
	bottom: LONG,
};

pub const WNDCLASSEXA = extern struct {
    cbSize: UINT,
    style: UINT,

    lpfnWndProc: WNDPROC,
    cbClsExtra: INT,
    cbWndExtra: INT,
    hInstance: ?HINSTANCE,
    hIcon: ?HICON,
    hCursor: ?HCURSOR,
    hbrBackground: ?HBRUSH,
    lpszMenuName: ?LPCSTR,
    lpszClassName: ?LPCSTR,
    hIconSm: ?HICON,
};



pub const MSG = extern struct {
	hwnd: HWND,
	message: MESSAGE,
	wParam: WPARAM,
	lParam: LPARAM,
	time: DWORD,
	pt: POINT,


	pub const MESSAGE = enum(UINT) {
		WM_NULL =		0x0000,
		WM_CREATE =		0x0001,
		WM_DESTROY =	0x0002,
		WM_MOVE =		0x0003,
		WM_SIZE =		0x0005,

		WM_ACTIVATE =	0x0006,

		
		WM_QUIT =		0x0012,

		WM_SYSCOMMAND =	0x0112,
		_
	};
};


pub const CS_VREDRAW         : UINT = 0x0001;
pub const CS_HREDRAW         : UINT = 0x0002;
pub const CS_DBLCLKS         : UINT = 0x0008;
pub const CS_OWNDC           : UINT = 0x0020;
pub const CS_CLASSDC         : UINT = 0x0040;
pub const CS_PARENTDC        : UINT = 0x0080;
pub const CS_NOCLOSE         : UINT = 0x0200;
pub const CS_SAVEBITS        : UINT = 0x0800;
pub const CS_BYTEALIGNCLIENT : UINT = 0x1000;
pub const CS_BYTEALIGNWINDOW : UINT = 0x2000;
pub const CS_GLOBALCLASS     : UINT = 0x4000;


pub const WS_OVERLAPPED       : DWORD = 0x00000000;
pub const WS_POPUP            : DWORD = 0x80000000;
pub const WS_CHILD            : DWORD = 0x40000000;
pub const WS_MINIMIZE         : DWORD = 0x20000000;
pub const WS_VISIBLE          : DWORD = 0x10000000;
pub const WS_DISABLED         : DWORD = 0x08000000;
pub const WS_CLIPSIBLINGS     : DWORD = 0x04000000;
pub const WS_CLIPCHILDREN     : DWORD = 0x02000000;
pub const WS_MAXIMIZE         : DWORD = 0x01000000;
pub const WS_CAPTION          : DWORD = 0x00C00000;
pub const WS_BORDER           : DWORD = 0x00800000;
pub const WS_DLGFRAME         : DWORD = 0x00400000;
pub const WS_VSCROLL          : DWORD = 0x00200000;
pub const WS_HSCROLL          : DWORD = 0x00100000;
pub const WS_SYSMENU          : DWORD = 0x00080000;
pub const WS_THICKFRAME       : DWORD = 0x00040000;
pub const WS_GROUP            : DWORD = 0x00020000;
pub const WS_TABSTOP          : DWORD = 0x00010000;

pub const WS_MINIMIZEBOX      : DWORD = 0x00020000;
pub const WS_MAXIMIZEBOX      : DWORD = 0x00010000;


pub const WS_OVERLAPPEDWINDOW : DWORD = (WS_OVERLAPPED     |
                             			 WS_CAPTION        |
                                         WS_SYSMENU        |
                                         WS_THICKFRAME     |
                                         WS_MINIMIZEBOX    |
                                         WS_MAXIMIZEBOX);

pub const WS_POPUPWINDOW : DWORD = (WS_POPUP          |
                             		WS_BORDER         |
                             		WS_SYSMENU);

pub const WS_CHILDWINDOW: DWORD =     (WS_CHILD);



//
// ShowWindow() Commands
//
pub const SW_HIDE              : INT = 0;
pub const SW_SHOWNORMAL        : INT = 1;
pub const SW_NORMAL            : INT = 1;
pub const SW_SHOWMINIMIZED     : INT = 2;
pub const SW_SHOWMAXIMIZED     : INT = 3;
pub const SW_MAXIMIZE          : INT = 3;
pub const SW_SHOWNOACTIVATE    : INT = 4;
pub const SW_SHOW              : INT = 5;
pub const SW_MINIMIZE          : INT = 6;
pub const SW_SHOWMINNOACTIVE   : INT = 7;
pub const SW_SHOWNA            : INT = 8;
pub const SW_RESTORE           : INT = 9;
pub const SW_SHOWDEFAULT       : INT = 10;
pub const SW_FORCEMINIMIZE     : INT = 11;
pub const SW_MAX               : INT = 11;


pub const CreateWindowExA = raw.CreateWindowExA;
pub const ShowWindow = raw.ShowWindow;
pub const UpdateWindow = raw.UpdateWindow;
pub const DispatchMessageA = raw.DispatchMessageA;
pub const TranslateMessage = raw.TranslateMessage;
pub const DefWindowProcA = raw.DefWindowProcA;
pub const GetModuleHandleA = raw.GetModuleHandleA;
pub const PostQuitMessage = raw.PostQuitMessage;


pub const PeekMessageOption = enum(UINT) {
	NOREMOVE          = 0x0000,
	REMOVE            = 0x0001,
	NOYIELD           = 0x0002,
};

// Dispatches incoming nonqueued messages, checks the thread message queue for a posted message, and retrieves the message (if any exist).
pub fn PeekMessageA( hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT, wRemoveMsg: PeekMessageOption ) ?MSG
{
	var msg: MSG = undefined;
	if ( raw.PeekMessageA( &msg, hWnd, wMsgFilterMin, wMsgFilterMax, @intFromEnum( wRemoveMsg ) ) != 0 )
	{
		return msg;
	}
	return null;
}


pub fn RegisterClassExA( param1: *const WNDCLASSEXA ) !void
{
	if ( raw.RegisterClassExA( param1 ) == 0 ) 
	{
		switch ( win.GetLastError() ) {
			else => |err| return win.unexpectedError(err),
		}
	}
}



pub fn GetClientRect( hWnd: HWND ) error{Unexpected}!RECT
{
	var rect: RECT = undefined;
	if ( raw.GetClientRect( hWnd, &rect ) == 0 )
	{
		switch (win.GetLastError()) {
			else => |err| return win.unexpectedError(err),
		}
	}
	
	return rect;
}


pub const raw = struct {
	pub extern "user32" fn RegisterClassExA( wndClass: *const WNDCLASSEXA) callconv(WINAPI) ATOM;

	pub extern "user32" fn CreateWindowExA( dwExStyle: DWORD, lpClassName: ?LPCSTR, lpWindowName: LPCSTR, dwStyle: DWORD, X: INT, Y: INT, nWidth: INT, nHeight: INT, hWndParent: ?HWND, hMenu: ?HMENU, hInstance: ?HINSTANCE, lpParam: ?LPVOID) callconv(WINAPI) HWND;

	pub extern "user32" fn ShowWindow( hWnd: HWND, nCmdShow: INT ) callconv(WINAPI) BOOL;
	pub extern "user32" fn UpdateWindow( hWnd: HWND ) callconv(WINAPI) BOOL;

	pub extern "user32" fn PeekMessageA( lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT, wRemoveMsg: UINT ) callconv(WINAPI) BOOL;
	pub extern "user32" fn DispatchMessageA( lpMsg: *const MSG ) callconv(WINAPI) LRESULT;
	pub extern "user32" fn TranslateMessage( lpMsg: *const MSG ) callconv(WINAPI) BOOL;

	pub extern "user32" fn DefWindowProcA( hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(WINAPI) LRESULT;

	pub extern "user32" fn GetModuleHandleA( lpModuleName: ?LPCSTR ) callconv(WINAPI) HMODULE;

	pub extern "user32" fn GetClientRect( hWnd: HWND, lpRect: *RECT ) callconv(WINAPI) BOOL;

	pub extern "user32" fn PostQuitMessage( nExitCode: c_int ) callconv(WINAPI) void;
};
