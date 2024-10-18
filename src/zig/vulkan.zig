const vulkan = @cImport({
	@cInclude("vulkan/vulkan.h");
	@cInclude("external/imgui/imgui_impl_vulkan.h");
});

pub usingnamespace vulkan;

const win = @import("std").os.windows;
const winuser = @import("winuser.zig");


const HWND = win.HWND;
const HINSTANCE = win.HINSTANCE;


const VkWin32SurfaceCreateInfoKHR = extern struct {
	sType: vulkan.VkStructureType,
	pNext: ?*opaque{},
	flags: vulkan.VkFlags,
	hinstance: HINSTANCE,
	hwnd: HWND
};



extern "vulkan-1" fn vkCreateWin32SurfaceKHR( instance: vulkan.VkInstance, createInfo: *const VkWin32SurfaceCreateInfoKHR, allocator: ?*vulkan.VkAllocationCallbacks, surface: *vulkan.VkSurfaceKHR ) callconv(.C) c_int;


pub fn createSurface( hwnd: win.HWND, instance: vulkan.VkInstance ) vulkan.VkSurfaceKHR
{
	
	const hinstance: HINSTANCE = @ptrCast( winuser.GetModuleHandleA( null ) );

	const createInfo : VkWin32SurfaceCreateInfoKHR = .{
		.sType = vulkan.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
		.pNext = null,
		.flags = 0,
		.hinstance = hinstance,
		.hwnd = hwnd,
	};


	var surface : vulkan.VkSurfaceKHR = undefined;
	_ = vkCreateWin32SurfaceKHR( instance, &createInfo, null, &surface );

	return surface;
}