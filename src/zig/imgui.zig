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

pub fn GetIDStr( str_id: []const u8 ) r.ImGuiID
{
	return ImGui_GetIDStr( str_id.ptr, str_id.ptr + str_id.len );
}

pub fn DockSpace( args: struct {
	dockspace_id: r.ImGuiID, size: r.ImVec2 = .{ .x=0, .y=0 }, flags: r.ImGuiDockNodeFlags = 0, window_class: ?*r.ImGuiWindowClass = null
}) r.ImGuiID
{
	return ImGui_DockSpace( args.dockspace_id, args.size, args.flags, args.window_class );
}


pub const SetNextWindowViewport = ImGui_SetNextWindowViewport;

extern fn ImGui_GetIO() callconv(.C) *r.ImGuiIO;
extern fn ImGui_SetNextWindowPos( pos: r.ImVec2, cond: r.ImGuiCond, pivot: r.ImVec2) callconv(.C) void;
extern fn ImGui_SetNextWindowSize( size: r.ImVec2, cond: r.ImGuiCond ) callconv(.C) void;
extern fn ImGui_SetNextWindowViewport( viewport_id: r.ImGuiID ) callconv(.C) void;


extern fn ImGui_GetIDStr( str_id_begin: [*]const u8, str_id_end: [*]const u8 ) callconv(.C) r.ImGuiID;
extern fn ImGui_DockSpace( dockspace_id: r.ImGuiID, size: r.ImVec2, flags: r.ImGuiDockNodeFlags, window_class: ?*r.ImGuiWindowClass ) callconv(.C) r.ImGuiID;
