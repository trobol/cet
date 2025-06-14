const std = @import("std");
const user32 = @import("winuser.zig");
const Arena = @import("arena.zig");
const vk = @import("vulkan.zig");
const imgui = @import("imgui.zig");
const tree_pane = @import("core_gui.zig");
const sqlite = @import("sqlite.zig");
const win = std.os.windows;

const assert = std.debug.assert;


extern fn ImGui_ImplWin32_WndProcHandler( hWnd: user32.HWND, msg: user32.UINT, wParam: user32.WPARAM, lParam: user32.LPARAM ) callconv(.C) user32.LRESULT;
fn WndProc(hWnd: user32.HWND, msg: user32.UINT, wParam: user32.WPARAM, lParam: user32.LPARAM) callconv(user32.WINAPI) user32.LRESULT 
{
	if ( ImGui_ImplWin32_WndProcHandler(hWnd, msg, wParam, lParam) != 0 )
		return 1;

	switch ( @as( user32.MSG.MESSAGE, @enumFromInt( msg ) ) )
	{
		.WM_SIZE => {
			//if (wParam == SIZE_MINIMIZED)
			//return 0;
			//g_ResizeWidth = (UINT)LOWORD(lParam); // Queue resize
			//g_ResizeHeight = (UINT)HIWORD(lParam);
			return 0;
		},

		.WM_SYSCOMMAND => {
			if ((wParam & 0xfff0) == 0xF100) // SC_KEYMENU Disable ALT application menu
				return 0;
		},
		.WM_DESTROY => {
			user32.PostQuitMessage(0);
			return 0;
		},
		else => {}
	}

	return user32.DefWindowProcA(hWnd, msg, wParam, lParam);
}


pub fn main() !void {
	const arena = Arena.Arena.init();
	const wc: user32.WNDCLASSEXA = .{
		.cbSize = @sizeOf(user32.WNDCLASSEXA),
		.style=0x0040,
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

	try user32.RegisterClassExA( &wc );

	const hwnd = user32.CreateWindowExA( 
		0,
		wc.lpszClassName,
		"ImGui Standalone",
		user32.WS_OVERLAPPEDWINDOW,
		100, 100,
		1280, 800,
		null, null,
		@ptrCast( wc.hInstance ), null
	);
	
	const extensions = [_][*:0]const u8{
		"VK_KHR_surface",
		"VK_KHR_win32_surface",
		"VK_EXT_debug_utils",
	};
	const gfx = setupVulkan( arena, extensions[0..], hwnd );

	var wd = vk.ImGui_ImplVulkanH_Window{};
	setupVulkanWindow( &wd, gfx, 1280, 800 );


	imgui.CreateContext();

	imgui.GetIO().ConfigFlags |= imgui.r.ImGuiConfigFlags_DockingEnable;

	_ = imgui.win.ImGui_ImplWin32_Init(hwnd);

	var init_info = vk.ImGui_ImplVulkan_InitInfo{
		.Instance = gfx.instance,
		.PhysicalDevice = gfx.phy_device,
		.Device = gfx.device,
		.QueueFamily = gfx.queue_family,
		.Queue = gfx.queue,
		.PipelineCache = null,
		.DescriptorPool = gfx.descriptor_pool,
		.RenderPass = wd.RenderPass,
		.Subpass = 0,
		.MinImageCount = 2,
		.ImageCount = wd.ImageCount,
		.MSAASamples = vk.VK_SAMPLE_COUNT_1_BIT,
		.Allocator = null,
		.CheckVkResultFn = null,
	};
	_ = vk.ImGui_ImplVulkan_Init( &init_info );

	
	_ = user32.ShowWindow( hwnd, user32.SW_SHOWDEFAULT );
	assert( user32.UpdateWindow( hwnd ) != 0 );

	var quit = false;
	while ( true )
	{
		while( user32.PeekMessageA( null, 0, 0, .REMOVE ) ) |msg|
		{

			_ = user32.TranslateMessage(&msg);
			_ = user32.DispatchMessageA(&msg);
			if (msg.message == .WM_QUIT) // WM_QUIT
				quit = true;
		}

		if (quit) break;

		const area = try user32.GetClientRect( hwnd );

		vk.ImGui_ImplVulkan_SetMinImageCount( 2 );
		vk.ImGui_ImplVulkanH_CreateOrResizeWindow( gfx.instance, gfx.phy_device, gfx.device, &wd, gfx.queue_family, null, area.right, area.bottom, 2 );

		imgui.win.ImGui_ImplWin32_NewFrame();
		vk.ImGui_ImplVulkan_NewFrame();

		imgui.r.ImGui_NewFrame();



		var window_flags = imgui.r.ImGuiWindowFlags_MenuBar | imgui.r.ImGuiWindowFlags_NoDocking;
		window_flags |= imgui.r.ImGuiWindowFlags_NoTitleBar | imgui.r.ImGuiWindowFlags_NoCollapse | imgui.r.ImGuiWindowFlags_NoResize | imgui.r.ImGuiWindowFlags_NoMove;
		window_flags |= imgui.r.ImGuiWindowFlags_NoBringToFrontOnFocus | imgui.r.ImGuiWindowFlags_NoNavFocus;
		
		const viewport = imgui.GetMainViewport();

		imgui.SetNextWindowPos( .{ .pos = viewport.*.WorkPos } );
		imgui.SetNextWindowSize( .{ .size = viewport.*.WorkSize } );
		imgui.SetNextWindowViewport( viewport.*.ID );

		_ = imgui.Begin( "test tp", null, window_flags );

		const dockspace_id = imgui.GetIDStr( "MyDockSpace" );
		_ = imgui.DockSpace(.{ .dockspace_id = dockspace_id } );

		if ( imgui.BeginMenuBar() ) {
			if ( imgui.BeginMenu( "File" ) ) {
				if ( imgui.MenuItem( .{ .label = "Load" } ) )
				{ 

				}
			
				imgui.EndMenu();
			}
			imgui.EndMenuBar();
		}

		var show_demo_window: bool = true;
		imgui.ShowDemoWindow(&show_demo_window);

		imgui.End();
		imgui.Render();

		imgui.r.ImGui_UpdatePlatformWindows();
		imgui.r.ImGui_RenderPlatformWindowsDefault();

		const main_draw_data = imgui.GetDrawData();
		const swapchain_rebuild = frameRender( gfx, &wd, main_draw_data );
		_ = framePresent( gfx, &wd );
		_ = swapchain_rebuild;
	}
}

fn framePresent( gfx: GfxInstance, wd: *vk.ImGui_ImplVulkanH_Window ) bool
{
	const render_complete_semaphore = wd.FrameSemaphores[wd.SemaphoreIndex].RenderCompleteSemaphore;
	const info = vk.VkPresentInfoKHR{
		.sType = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
		.waitSemaphoreCount = 1,
		.pWaitSemaphores = &render_complete_semaphore,
		.swapchainCount = 1,
		.pSwapchains = &wd.Swapchain,
		.pImageIndices = &wd.FrameIndex,
	};
	const err = vk.vkQueuePresentKHR(gfx.queue, &info);
	if (err == vk.VK_ERROR_OUT_OF_DATE_KHR or err == vk.VK_SUBOPTIMAL_KHR)
	{
		return true;
	}

	wd.SemaphoreIndex = (wd.SemaphoreIndex + 1) % wd.SemaphoreCount;

	return false;
}

fn frameRender( gfx: GfxInstance, wd: *vk.ImGui_ImplVulkanH_Window, draw_data: *imgui.r.ImDrawData ) bool 
{
	var err: vk.VkResult = undefined;

	const image_acquired_semaphore = wd.FrameSemaphores[wd.SemaphoreIndex].ImageAcquiredSemaphore;
	const render_complete_semaphore = wd.FrameSemaphores[wd.SemaphoreIndex].RenderCompleteSemaphore;
	err = vk.vkAcquireNextImageKHR(gfx.device, wd.Swapchain, vk.UINT64_MAX, image_acquired_semaphore, null, &wd.FrameIndex);
	if ( err == vk.VK_ERROR_OUT_OF_DATE_KHR or err == vk.VK_SUBOPTIMAL_KHR )
	{
		return true;
	}

	const fd = &wd.Frames[wd.FrameIndex];
	err = vk.vkWaitForFences(gfx.device, 1, &fd.Fence, vk.VK_TRUE, vk.UINT64_MAX);
	err = vk.vkResetFences(gfx.device, 1, &fd.Fence );


	err = vk.vkResetCommandPool(gfx.device, fd.CommandPool, 0);

	const buffer_info = vk.VkCommandBufferBeginInfo{
		.sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
		.flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
	};
	err = vk.vkBeginCommandBuffer(fd.CommandBuffer, &buffer_info);


	const pass_info = vk.VkRenderPassBeginInfo{
		.sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
		.renderPass = wd.RenderPass,
		.framebuffer = fd.Framebuffer,
		.renderArea = .{
			.offset = .{ .x = 0, .y = 0 },
			.extent = .{ .width = @intCast(wd.Width), .height = @intCast(wd.Height) }
		},
		.clearValueCount = 1,
		.pClearValues = &wd.ClearValue,
	};
	vk.vkCmdBeginRenderPass(fd.CommandBuffer, &pass_info, vk.VK_SUBPASS_CONTENTS_INLINE);

	vk.ImGui_ImplVulkan_RenderDrawData(@ptrCast(draw_data), fd.CommandBuffer, null);
	
	vk.vkCmdEndRenderPass(fd.CommandBuffer);

	
	const wait_stage: u32 = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
	const submit_info = vk.VkSubmitInfo{
		.sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
		.waitSemaphoreCount = 1,
		.pWaitSemaphores = &image_acquired_semaphore,
		.pWaitDstStageMask = &wait_stage,
		.commandBufferCount = 1,
		.pCommandBuffers = &fd.CommandBuffer,
		.signalSemaphoreCount = 1,
		.pSignalSemaphores = &render_complete_semaphore
	};

	err = vk.vkEndCommandBuffer( fd.CommandBuffer );
	err = vk.vkQueueSubmit( gfx.queue, 1, &submit_info, fd.Fence );

	return false;
}

fn SetupVulkan_SelectPhysicalDevice( _scratchArena: Arena.Arena, instance: vk.VkInstance ) vk.VkPhysicalDevice
{
	var scratchArena = _scratchArena;
	var gpu_count : u32 = undefined;
	_ = vk.vkEnumeratePhysicalDevices( instance, &gpu_count, null );

	
	const gpus = scratchArena.alloc(vk.VkPhysicalDevice, gpu_count);
	_ = vk.vkEnumeratePhysicalDevices( instance, &gpu_count, gpus.ptr );

	for (gpus) |device|
	{
		var properties: vk.VkPhysicalDeviceProperties = undefined;
		vk.vkGetPhysicalDeviceProperties( device, &properties );
		if ( properties.deviceType == vk.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU )
		{
			return device;
		}
	}

	return gpus[0];
}

const GfxInstance = struct {
	instance: vk.VkInstance,
	phy_device: vk.VkPhysicalDevice,
	queue_family: u32,
	device: vk.VkDevice,
	queue: vk.VkQueue,
	descriptor_pool: vk.VkDescriptorPool,
	surface: vk.VkSurfaceKHR,
};

fn setupVulkanWindow( wd: *vk.ImGui_ImplVulkanH_Window, gfx: GfxInstance, width: c_int, height: c_int ) void
{
	wd.Surface = gfx.surface;

	var res: vk.VkBool32 = undefined;
	_ = vk.vkGetPhysicalDeviceSurfaceSupportKHR( gfx.phy_device, gfx.queue_family, gfx.surface, &res);
	if (res != vk.VK_TRUE)
	{
		std.debug.panic("Error no WSI support on physical device 0\n", .{});
	}

	// Select Surface Format
	const requestSurfaceImageFormat = &[_]c_uint{
		vk.VK_FORMAT_B8G8R8A8_UNORM,
		vk.VK_FORMAT_R8G8B8A8_UNORM,
		vk.VK_FORMAT_B8G8R8_UNORM,
		vk.VK_FORMAT_R8G8B8_UNORM
	};
	const requestSurfaceColorSpace: vk.VkColorSpaceKHR = vk.VK_COLORSPACE_SRGB_NONLINEAR_KHR;
	wd.SurfaceFormat = vk.ImGui_ImplVulkanH_SelectSurfaceFormat( gfx.phy_device, gfx.surface, requestSurfaceImageFormat, requestSurfaceImageFormat.len, requestSurfaceColorSpace);

	const present_modes = &[_]c_uint{ vk.VK_PRESENT_MODE_FIFO_KHR };
	wd.PresentMode = vk.ImGui_ImplVulkanH_SelectPresentMode( gfx.phy_device, gfx.surface, present_modes, present_modes.len );

	vk.ImGui_ImplVulkanH_CreateOrResizeWindow( gfx.instance, gfx.phy_device, gfx.device, wd, gfx.queue_family, null, width, height, 2 );
}

fn setupVulkan( _scratchArena: Arena.Arena, instance_extensions: []const [*:0]const u8, hwnd: win.HWND ) GfxInstance
{
	var scratchArena = _scratchArena;
	var instance : vk.VkInstance = undefined;
	const createInfo : vk.VkInstanceCreateInfo = .{
		.sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
		.ppEnabledExtensionNames = instance_extensions.ptr,
		.enabledExtensionCount = @truncate( instance_extensions.len )
	};

	_ = vk.vkCreateInstance( &createInfo, null, &instance );

	const phy_device = SetupVulkan_SelectPhysicalDevice( scratchArena, instance );

	var count: u32 = undefined;
	vk.vkGetPhysicalDeviceQueueFamilyProperties( phy_device, &count, null );
	const queues = scratchArena.alloc(vk.VkQueueFamilyProperties, count);
	vk.vkGetPhysicalDeviceQueueFamilyProperties( phy_device, &count, queues.ptr );

	const queue_idx: u32 = for ( queues, 0.. ) |queue, idx|
	{
		if ( (queue.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT) == vk.VK_QUEUE_GRAPHICS_BIT )
			break @truncate( idx );
	} else unreachable;


	const queue_priority = [_]f32{ 1.0 };

	const queue_info = [_]vk.VkDeviceQueueCreateInfo{
		.{
			.sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
			.queueFamilyIndex = queue_idx,
			.queueCount = @truncate(queue_priority.len),
			.pQueuePriorities = &queue_priority,
		}
	};

	const device_extensions = [_][*:0]const u8{
		"VK_KHR_swapchain"
	};

	const create_info : vk.VkDeviceCreateInfo = .{
		.sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
		.queueCreateInfoCount = queue_info.len,
		.pQueueCreateInfos = &queue_info,
		.enabledExtensionCount = device_extensions.len,
		.ppEnabledExtensionNames = &device_extensions
	};

	var device : vk.VkDevice = undefined;
	_ = vk.vkCreateDevice( phy_device, &create_info, null, &device );

	var queue: vk.VkQueue = undefined;
	_ = vk.vkGetDeviceQueue( device, queue_idx, 0, &queue );

	const pool_sizes = [_]vk.VkDescriptorPoolSize{
		.{ .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount=1 }
	};

	const pool_info = vk.VkDescriptorPoolCreateInfo{
		.sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
		.flags = vk.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
		.maxSets = 1,
		.pPoolSizes = &pool_sizes,
		.poolSizeCount = pool_sizes.len
	};

	var descriptor_pool : vk.VkDescriptorPool = undefined;
	_ = vk.vkCreateDescriptorPool( device, &pool_info, null, &descriptor_pool );

	const surface = vk.createSurface( hwnd, instance );

	return .{
		.device = device,
		.phy_device = phy_device,
		.queue_family = queue_idx,
		.queue = queue,
		.instance = instance,
		.descriptor_pool = descriptor_pool,
		.surface = surface,
	};
}






