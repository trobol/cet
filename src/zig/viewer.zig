const std = @import("std");
const user32 = @import("winuser.zig");

const win: type = std.os.windows;


fn WndProc(hWnd: user32.HWND, msg: user32.UINT, wParam: user32.WPARAM, lParam: user32.LPARAM) callconv(user32.WINAPI) {
	return user32.DefWindowProcA(hWnd, msg, wParam, lParam);
}

pub fn main() void {

	const wc: user32.WNDCLASSEXA = .{
		.cbSize = @sizeOf(user32.WNDCLASSEXA),
		.style=user32.CS_CLASSDC,
		.lpfnWndProc = WndProc,
		.cbClsExtra=0,
		.cbWndExtra = 0,
		.hInstance = GetModuleHandleA( null ),
	};

	
	var running = true;

	while ( running )
	{
		var msg: user32.MSG = undefined;

	}
}