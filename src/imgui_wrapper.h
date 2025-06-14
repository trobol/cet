#include <external/imgui/imgui.h>

#ifdef __cplusplus
extern "C" {
#endif
void ImGui_CreateContext();



void ImGui_NewFrame();
void ImGui_EndFrame();
void ImGui_Render();

struct ImGuiViewport* ImGui_GetMainViewport();

bool ImGui_Begin(const char* name, const char* name_end, bool* p_open, ImGuiWindowFlags flags);
void ImGui_End();

void ImGui_TextEx(const char* text, const char* text_end, int /*ImGuiTextFlags*/ flags);

bool ImGui_Checkbox(const char* label, const char* label_end, bool* v);

bool ImGui_BeginMenuBar();
void ImGui_EndMenuBar();

bool ImGui_BeginMenu( const char* label, const char* label_end, bool enabled );
void ImGui_EndMenu();

bool ImGui_MenuItemEx(const char* label, const char* label_end, const char* shortcut, bool selected, bool enabled);


bool ImGui_SliderScalarN(const char* label, ImGuiDataType data_type, void* v, int components, const void* v_min, const void* v_max, const char* format, ImGuiSliderFlags flags);
bool ImGui_ButtonEx(const char* label, const ImVec2* size_arg, int /*ImGuiButtonFlags*/ flags);

void ImGui_SameLine(float offset_from_start_x, float spacing);

void ImGui_PopStyleVar();


void ImGui_ShowDemoWindow(bool* p_open);


ImDrawData* ImGui_GetDrawData();

void ImGui_UpdatePlatformWindows();
void ImGui_RenderPlatformWindowsDefault();


#ifdef __cplusplus
} // extern "C"
#endif