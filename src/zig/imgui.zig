const std = @import("std");

pub const r = @cImport({
	@cDefine("IM_NO_CXX", "1");
	@cInclude("imgui_wrapper.h");
});

pub const win = @cImport({
	@cDefine("IM_NO_CXX", "1");
	@cInclude("external/imgui/imgui_impl_win32.h");
});





pub fn GetDrawData() *r.ImDrawData
{
	return r.ImGui_GetDrawData() orelse unreachable;
}

