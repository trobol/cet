const std = @import("std");
const user32 = @import("winuser.zig");

const win: type = std.os.windows;


fn WndProc(hWnd: user32.HWND, msg: user32.UINT, wParam: user32.WPARAM, lParam: user32.LPARAM) callconv(user32.WINAPI) user32.LRESULT 
{
	return user32.DefWindowProcA(hWnd, msg, wParam, lParam);
}


const assert = std.debug.assert;

pub fn main() !void {

	const wc: user32.WNDCLASSEXA = .{
		.cbSize = @sizeOf(user32.WNDCLASSEXA),
		.style=0,
		.lpfnWndProc = WndProc,
		.cbClsExtra=0,
		.cbWndExtra = 0,
		.hInstance = @as( win.HINSTANCE, @ptrCast( user32.GetModuleHandleA( null ) ) ),
		.hIcon = null,
		.hCursor = null,
		.hbrBackground = null,
		.lpszMenuName = null,
		.lpszClassName = "ImGui Standalone",
		.hIconSm = null,
	};

	if  ( user32.RegisterClassExA( &wc ) == 0 ) 
	{
		switch (win.GetLastError()) {
            else => |err| return win.unexpectedError(err),
        }
	}

	const hwnd = user32.CreateWindowExA( 
		0,
		wc.lpszClassName,
		"ImGui Standalone",
		user32.WS_OVERLAPPED,
		100, 100,
		50, 50,
		null, null,
		@ptrCast( wc.hInstance ), null
	);




	_ = user32.ShowWindow( hwnd, user32.SW_SHOWDEFAULT );
	assert( user32.UpdateWindow( hwnd ) != 0 );

	
	var running = true;

	while ( running )
	{
		var msg: user32.MSG = undefined;
		while(user32.PeekMessageA(&msg, null, 0, 0, 1) != 0)
		{
			_ = user32.TranslateMessage(&msg);
			_ = user32.DispatchMessageA(&msg);
			if (msg.message == 0x0012) // WM_QUIT
				running = false;
		}
	}
}