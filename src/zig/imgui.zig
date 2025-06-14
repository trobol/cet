const std = @import("std");

pub const r = @cImport({
	@cDefine("IM_NO_CXX", "1");
	@cInclude("imgui_wrapper.h");
});

pub const win = @cImport({
	@cDefine("IM_NO_CXX", "1");
	@cInclude("external/imgui/imgui_impl_win32.h");
});





pub const GetMainViewport = r.ImGui_GetMainViewport;
pub const End = r.ImGui_End;
pub const Render = r.ImGui_Render;
pub const CreateContext = r.ImGui_CreateContext;
pub const BeginMenuBar = r.ImGui_BeginMenuBar;
pub const EndMenu = r.ImGui_EndMenu;
pub const EndMenuBar = r.ImGui_EndMenuBar;


pub fn MenuItem( args: struct {
	label: []const u8,
	selected: bool = false,
	enabled: bool = true
}) bool 
{
	// TODO: shortcut and icon
	return r.ImGui_MenuItemEx( args.label.ptr, args.label.ptr + args.label.len, null, args.selected, args.enabled );
}

pub fn BeginMenu( name: []const u8 ) bool
{
	return r.ImGui_BeginMenu( name.ptr, name.ptr + name.len, true );
}


pub fn Begin( name: []const u8, p_open: ?*bool, flags: c_int ) bool
{
	return r.ImGui_Begin( name.ptr, name.ptr + name.len, p_open, flags );
}


pub const ShowDemoWindow = r.ImGui_ShowDemoWindow;


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
