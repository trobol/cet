#include <imgui_wrapper.h>
#include <external/imgui/imgui_internal.h>

extern "C" {
void ImGui_CreateContext()
{
	ImGui::CreateContext();
}

void ImGui_NewFrame()
{
	ImGui::NewFrame();
}

void ImGui_EndFrame()
{
	ImGui::EndFrame();
}

void ImGui_Render()
{
	ImGui::Render();
}

ImGuiViewport* ImGui_GetMainViewport()
{
	return ImGui::GetMainViewport();
}


bool ImGui_Begin(const char* name, const char* name_end, bool* p_open, ImGuiWindowFlags flags)
{
	return ImGui::Begin(name, name_end, p_open, flags);
}

void ImGui_End()
{
	ImGui::End();
}

bool ImGui_BeginMenuBar()
{
	return ImGui::BeginMenuBar();
}

void ImGui_EndMenuBar()
{
	ImGui::EndMenuBar();
}

bool ImGui_BeginMenu( const char* label, const char* label_end, bool enabled )
{
	return ImGui::BeginMenuEx( label, label_end, NULL, enabled );
}

void ImGui_EndMenu()
{
	return ImGui::EndMenu();
}

bool ImGui_MenuItemEx(const char* label, const char* label_end, const char* shortcut, bool selected, bool enabled)
{	
	// TODO: figure out what icon is doing here
	return ImGui::MenuItemEx( label, label_end, NULL, shortcut, selected, enabled );
}


void ImGui_TextEx(const char* text, const char* text_end, ImGuiTextFlags flags)
{
	ImGui::TextEx(text, text_end, flags);
}

bool ImGui_Checkbox(const char* label, const char* label_end, bool* v)
{
	return ImGui::Checkbox(label, label_end, v);
}

bool ImGui_SliderScalarN(const char* label, ImGuiDataType data_type, void* v, int components, const void* v_min, const void* v_max, const char* format, ImGuiSliderFlags flags)
{
	return ImGui::SliderScalarN(label, data_type, v, components, v_min, v_max, format, flags);
}

bool ImGui_ButtonEx(const char* label, const ImVec2* size_arg, ImGuiButtonFlags flags)
{
	return ImGui::ButtonEx(label, *size_arg, flags);
}

void ImGui_SameLine(float offset_from_start_x, float spacing)
{
	ImGui::SameLine(offset_from_start_x, spacing);
}

void ImGui_PopStyleVar()
{
	ImGui::PopStyleVar();
}

void ImGui_ShowDemoWindow(bool* p_open)
{
	ImGui::ShowDemoWindow( p_open );
}

ImDrawData* ImGui_GetDrawData()
{
	return ImGui::GetDrawData();
}

void ImGui_UpdatePlatformWindows()
{
	ImGui::UpdatePlatformWindows();
}

void ImGui_RenderPlatformWindowsDefault()
{
	ImGui::RenderPlatformWindowsDefault();
}

ImGuiIO* ImGui_GetIO()
{
	return &ImGui::GetIO();
}

void ImGui_SetNextWindowPos( ImVec2 pos, ImGuiCond cond, ImVec2 pivot) 
{
	ImGui::SetNextWindowPos( pos, cond, pivot );
}

void ImGui_SetNextWindowSize( ImVec2 size, ImGuiCond cond ) 
{
	ImGui::SetNextWindowSize( size, cond );
}

void ImGui_SetNextWindowViewport( ImGuiID viewport_id ) 
{
	ImGui::SetNextWindowViewport( viewport_id );
}

ImGuiID ImGui_GetIDStr( const char* str_id_begin, const char* str_id_end )
{
	return ImGui::GetID( str_id_begin, str_id_end );
}

ImGuiID ImGui_DockSpace(ImGuiID dockspace_id, ImVec2 size, ImGuiDockNodeFlags flags, const ImGuiWindowClass* window_class )
{
	return ImGui::DockSpace( dockspace_id, size, flags, window_class );
}

}