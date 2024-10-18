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


void ImGui_Begin(const char* name, bool* p_open, ImGuiWindowFlags flags)
{
	ImGui::Begin(name, p_open, flags);
}

void ImGui_End()
{
	ImGui::End();
}

void ImGui_TextEx(const char* text, const char* text_end, ImGuiTextFlags flags)
{
	ImGui::TextEx(text, text_end, flags);
}

bool ImGui_Checkbox(const char* label, bool* v)
{
	return ImGui::Checkbox(label, v);
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

}