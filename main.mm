// Dear ImGui: standalone example application for SDL3 + Metal with SQLite runner
// Spawn multiple independent SQL query windows, each with its own DB path,
// editor, and results table — modelled on the HTTP request window pattern.

#include "imgui.h"
#include "imgui_impl_sdl3.h"
#include "imgui_impl_metal.h"

#include "sqlite3.h"

#include <stdio.h>
#include <string>
#include <vector>
#include <SDL3/SDL.h>

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

// ─────────────────────────────────────────────────────────────────────────────
// Data types
// ─────────────────────────────────────────────────────────────────────────────

struct QueryResult {
    std::vector<std::string>              columns;
    std::vector<std::vector<std::string>> rows;
};

struct SQLiteCallbackData {
    QueryResult* result;
    bool         header_captured;
};

// sqlite3_exec callback — accumulates rows into QueryResult
static int sqlite_callback(void* user_data, int col_count,
                            char** col_values, char** col_names)
{
    auto* cbd = static_cast<SQLiteCallbackData*>(user_data);

    if (!cbd->header_captured) {
        for (int i = 0; i < col_count; ++i)
            cbd->result->columns.push_back(col_names[i] ? col_names[i] : "");
        cbd->header_captured = true;
    }

    std::vector<std::string> row;
    row.reserve(col_count);
    for (int i = 0; i < col_count; ++i)
        row.push_back(col_values[i] ? col_values[i] : "NULL");
    cbd->result->rows.push_back(std::move(row));

    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-window state  (mirrors HTTPRequestWindow)
// ─────────────────────────────────────────────────────────────────────────────

struct SQLWindow {
    bool open = true;
    int  id;

    char db_path[512];
    char sql_buf[4096];

    QueryResult result;
    std::string error_msg;
    bool        has_result    = false;
    bool        has_error     = false;
    int         rows_affected = 0;

    explicit SQLWindow(int window_id) : id(window_id) {
        strcpy(db_path, "test.db");
        strcpy(sql_buf, "SELECT sqlite_version();");
    }

    void RunQuery() {
        result        = QueryResult{};
        error_msg     = "";
        has_result    = false;
        has_error     = false;
        rows_affected = 0;

        sqlite3* db = nullptr;
        if (sqlite3_open(db_path, &db) != SQLITE_OK) {
            error_msg = std::string("Cannot open database: ") + sqlite3_errmsg(db);
            has_error = true;
            sqlite3_close(db);
            return;
        }

        SQLiteCallbackData cbd{ &result, false };
        char* err_str = nullptr;
        int   rc      = sqlite3_exec(db, sql_buf, sqlite_callback, &cbd, &err_str);

        if (rc != SQLITE_OK) {
            error_msg = std::string("SQL error: ") + (err_str ? err_str : "unknown");
            has_error = true;
            sqlite3_free(err_str);
        } else {
            rows_affected = sqlite3_changes(db);
            has_result    = true;
        }

        sqlite3_close(db);
    }

    void ClearResults() {
        result        = QueryResult{};
        error_msg     = "";
        has_result    = false;
        has_error     = false;
        rows_affected = 0;
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// Render one SQL window  (query input + results in a single window)
// ─────────────────────────────────────────────────────────────────────────────

void ShowSQLWindow(SQLWindow& sw)
{
    char title[64];
    snprintf(title, sizeof(title), "SQL Query ##%d", sw.id);

    ImGui::SetNextWindowSize(ImVec2(660, 600), ImGuiCond_FirstUseEver);
    ImGui::Begin(title, nullptr);

    // ── Input section ──────────────────────────────────────────────────────
    ImGui::Text("Database path:");
    ImGui::SetNextItemWidth(-FLT_MIN);
    ImGui::InputText("##dbpath", sw.db_path, sizeof(sw.db_path));

    ImGui::Spacing();
    ImGui::Text("SQL statement:");
    ImGui::InputTextMultiline(
        "##sql",
        sw.sql_buf,
        sizeof(sw.sql_buf),
        ImVec2(-FLT_MIN, ImGui::GetTextLineHeight() * 8),
        ImGuiInputTextFlags_AllowTabInput
    );

    ImGui::Spacing();
    if (ImGui::Button("Run  \xe2\x96\xb6")) sw.RunQuery();   // UTF-8 ▶
    ImGui::SameLine();
    if (ImGui::Button("Clear"))             sw.ClearResults();
    ImGui::SameLine();
    if (ImGui::Button("Close Me"))          sw.open = false;  // mirrors HTTP window

    ImGui::Separator();

    // ── Results section ────────────────────────────────────────────────────
    ImGui::Text("Results:");
    ImGui::Spacing();

    if (sw.has_error) {
        ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 0.35f, 0.35f, 1.0f));
        ImGui::TextWrapped("%s", sw.error_msg.c_str());
        ImGui::PopStyleColor();

    } else if (sw.has_result) {
        if (sw.result.columns.empty()) {
            // Non-SELECT (INSERT / UPDATE / DELETE / CREATE …)
            ImGui::TextDisabled("Query OK \xe2\x80\x94 %d row(s) affected.", sw.rows_affected);
        } else {
            const int col_count = static_cast<int>(sw.result.columns.size());

            ImGuiTableFlags flags =
                ImGuiTableFlags_Borders        |
                ImGuiTableFlags_RowBg          |
                ImGuiTableFlags_ScrollX        |
                ImGuiTableFlags_ScrollY        |
                ImGuiTableFlags_SizingFixedFit;

            float table_h = ImGui::GetContentRegionAvail().y
                            - ImGui::GetTextLineHeightWithSpacing();
            if (ImGui::BeginTable("##results", col_count, flags,
                                  ImVec2(0.0f, table_h)))
            {
                ImGui::TableSetupScrollFreeze(0, 1);
                for (const auto& col_name : sw.result.columns)
                    ImGui::TableSetupColumn(col_name.c_str(),
                                            ImGuiTableColumnFlags_WidthFixed, 120.0f);
                ImGui::TableHeadersRow();

                for (const auto& row : sw.result.rows) {
                    ImGui::TableNextRow();
                    for (int c = 0; c < col_count; ++c) {
                        ImGui::TableSetColumnIndex(c);
                        ImGui::TextUnformatted(row[c].c_str());
                    }
                }
                ImGui::EndTable();
            }
            ImGui::TextDisabled("%zu row(s) returned.", sw.result.rows.size());
        }
    } else {
        ImGui::TextDisabled("Run a query to see results here.");
    }

    ImGui::End();
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

int main(int, char**)
{
    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMEPAD)) {
        printf("Error: SDL_Init(): %s\n", SDL_GetError());
        return 1;
    }

    float main_scale = SDL_GetDisplayContentScale(SDL_GetPrimaryDisplay());
    SDL_WindowFlags window_flags = SDL_WINDOW_METAL | SDL_WINDOW_RESIZABLE |
                                   SDL_WINDOW_HIDDEN | SDL_WINDOW_HIGH_PIXEL_DENSITY;
    SDL_Window* window = SDL_CreateWindow(
        "Dear ImGui SDL3+Metal \xe2\x80\x94 SQLite Runner",
        (int)(1280 * main_scale), (int)(800 * main_scale), window_flags);
    if (!window) { printf("Error: SDL_CreateWindow(): %s\n", SDL_GetError()); return 1; }
    SDL_SetWindowPosition(window, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
    SDL_ShowWindow(window);

    id<MTLDevice> metalDevice = MTLCreateSystemDefaultDevice();
    if (!metalDevice) {
        printf("Error: failed to create Metal device.\n");
        SDL_DestroyWindow(window); SDL_Quit(); return 1;
    }
    SDL_MetalView view  = SDL_Metal_CreateView(window);
    CAMetalLayer* layer = (__bridge CAMetalLayer*)SDL_Metal_GetLayer(view);
    layer.device        = metalDevice;
    layer.pixelFormat   = MTLPixelFormatBGRA8Unorm;

    id<MTLCommandQueue>      commandQueue         = [layer.device newCommandQueue];
    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;

    ImGui::StyleColorsDark();
    ImGuiStyle& style = ImGui::GetStyle();
    style.ScaleAllSizes(main_scale);
    style.FontScaleDpi = main_scale;

    ImGui_ImplMetal_Init(layer.device);
    ImGui_ImplSDL3_InitForMetal(window);

    float clear_color[4] = { 0.45f, 0.55f, 0.60f, 1.00f };

    std::vector<SQLWindow> sql_windows;
    int next_window_id  = 0;
    int max_sql_windows = 10;

    bool done = false;
    while (!done)
    {
        @autoreleasepool
        {
            SDL_Event event;
            while (SDL_PollEvent(&event)) {
                ImGui_ImplSDL3_ProcessEvent(&event);
                if (event.type == SDL_EVENT_QUIT) done = true;
                if (event.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED &&
                    event.window.windowID == SDL_GetWindowID(window))
                    done = true;
            }

            if (SDL_GetWindowFlags(window) & SDL_WINDOW_MINIMIZED) {
                SDL_Delay(10); continue;
            }

            int width, height;
            SDL_GetWindowSizeInPixels(window, &width, &height);
            layer.drawableSize = CGSizeMake(width, height);

            id<CAMetalDrawable> drawable = [layer nextDrawable];
            id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];

            renderPassDescriptor.colorAttachments[0].clearColor =
                MTLClearColorMake(clear_color[0] * clear_color[3],
                                  clear_color[1] * clear_color[3],
                                  clear_color[2] * clear_color[3],
                                  clear_color[3]);
            renderPassDescriptor.colorAttachments[0].texture     = drawable.texture;
            renderPassDescriptor.colorAttachments[0].loadAction  = MTLLoadActionClear;
            renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;

            id<MTLRenderCommandEncoder> renderEncoder =
                [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
            [renderEncoder pushDebugGroup:@"ImGui SQLite demo"];

            ImGui_ImplMetal_NewFrame(renderPassDescriptor);
            ImGui_ImplSDL3_NewFrame();
            ImGui::NewFrame();

            // ── 1. Control window ─────────────────────────────────────────
            {
                ImGui::Begin("SQL Manager");

                ImGui::SliderInt("Max Windows", &max_sql_windows, 1, 20);
                ImGui::ColorEdit3("clear color", clear_color);
                ImGui::Text("Open Windows: %d", (int)sql_windows.size());
                ImGui::Separator();

                if (ImGui::Button("New SQL Window")) {
                    if ((int)sql_windows.size() < max_sql_windows)
                        sql_windows.emplace_back(next_window_id++);
                }
                ImGui::SameLine();
                ImGui::Text("(%d/%d)", (int)sql_windows.size(), max_sql_windows);

                ImGui::Text("Application average %.3f ms/frame (%.1f FPS)",
                            1000.0f / io.Framerate, io.Framerate);
                ImGui::End();
            }

            // ── 2. SQL windows (spawn/close mirrors HTTP window loop) ──────
            for (size_t i = 0; i < sql_windows.size(); ) {
                SQLWindow& sw = sql_windows[i];
                if (sw.open) {
                    ShowSQLWindow(sw);
                    ++i;
                } else {
                    sql_windows.erase(sql_windows.begin() + i);
                }
            }

            // ── Rendering ─────────────────────────────────────────────────
            ImGui::Render();
            ImDrawData* draw_data = ImGui::GetDrawData();
            ImGui_ImplMetal_RenderDrawData(draw_data, commandBuffer, renderEncoder);

            [renderEncoder popDebugGroup];
            [renderEncoder endEncoding];
            [commandBuffer presentDrawable:drawable];
            [commandBuffer commit];
        }
    }

    ImGui_ImplMetal_Shutdown();
    ImGui_ImplSDL3_Shutdown();
    ImGui::DestroyContext();
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
