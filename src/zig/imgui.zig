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



pub const GetIO = ImGui_GetIO;



pub fn SetNextWindowPos( args: struct {
	pos: r.ImVec2,
	cond: r.ImGuiCond = 0,
	pivot: r.ImVec2 = .{ .x = 0, .y = 0 }
}) void
{
	ImGui_SetNextWindowPos(args.pos, args.cond, args.pivot);
}

pub fn SetNextWindowSize( args: struct {
	size: r.ImVec2,
	cond: r.ImGuiCond = 0
}) void 
{
	ImGui_SetNextWindowSize(args.size, args.cond);
}

pub const SetNextWindowViewport = ImGui_SetNextWindowViewport;

extern fn ImGui_GetIO() callconv(.C) *r.ImGuiIO;
extern fn ImGui_SetNextWindowPos( pos: r.ImVec2, cond: r.ImGuiCond, pivot: r.ImVec2) callconv(.C) void;
extern fn ImGui_SetNextWindowSize( size: r.ImVec2, cond: r.ImGuiCond ) callconv(.C) void;
extern fn ImGui_SetNextWindowViewport( viewport_id: r.ImGuiID ) callconv(.C) void;