
package shaderc

// @TODO Use shaderc in game instead of external glslc tool

// import "core:c"
// import "core:fmt"
// import "core:mem"

// // RAYLIB_WASM_LIB :: #config(RAYLIB_WASM_LIB, "wasm/libraylib.a")

// when ODIN_OS == .Windows {
// 	// @(extra_linker_flags="/NODEFAULTLIB:" + ("msvcrt" when RAYLIB_SHARED else "libcmt"))
// 	@(extra_linker_flags="/NODEFAULTLIB:" + ("libcmt"))
// 	foreign import lib {
// 		// "windows/raylibdll.lib" when RAYLIB_SHARED else "windows/raylib.lib" ,
// 		"windows/shaderc.lib",
// 		// "system:Winmm.lib",
// 		// "system:Gdi32.lib",
// 		// "system:User32.lib",
// 		// "system:Shell32.lib",
// 	}
// } else when ODIN_OS == .Linux  {
// 	// foreign import lib {
// 	// 	// Note(bumbread): I'm not sure why in `linux/` folder there are
// 	// 	// multiple copies of raylib.so, but since these bindings are for
// 	// 	// particular version of the library, I better specify it. Ideally,
// 	// 	// though, it's best specified in terms of major (.so.4)
// 	// 	"linux/libraylib.so.550" when RAYLIB_SHARED else "linux/libraylib.a",
// 	// 	"system:dl",
// 	// 	"system:pthread",
// 	// }
// } else when ODIN_OS == .Darwin {
// 	// foreign import lib {
// 	// 	"macos/libraylib.550.dylib" when RAYLIB_SHARED else "macos/libraylib.a",
// 	// 	"system:Cocoa.framework",
// 	// 	"system:OpenGL.framework",
// 	// 	"system:IOKit.framework",
// 	// } 
// } else when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
// 	// foreign import lib {
// 	// 	RAYLIB_WASM_LIB,
// 	// }
// } else {
// 	foreign import lib "system:shaderc"
// }

// @(default_calling_convention="c")
// foreign lib {
// 	//------------------------------------------------------------------------------------
// 	// Global Variables Definition
// 	//------------------------------------------------------------------------------------
// 	// It's lonely here...

// 	//------------------------------------------------------------------------------------
// 	// Window and Graphics Device Functions (Module: core)
// 	//------------------------------------------------------------------------------------

// 	// Window-related functions

// 	InitWindow               :: proc(width, height: c.int, title: cstring) ---  // Initialize window and OpenGL context
// 	WindowShouldClose        :: proc() -> bool  ---                             // Check if application should close (KEY_ESCAPE pressed or windows close icon clicked)
// 	CloseWindow              :: proc() ---                                      // Close window and unload OpenGL context
// 	IsWindowReady            :: proc() -> bool  ---                             // Check if window has been initialized successfully
// 	IsWindowFullscreen       :: proc() -> bool  ---                             // Check if window is currently fullscreen
// 	IsWindowHidden           :: proc() -> bool  ---                             // Check if window is currently hidden
// 	IsWindowMinimized        :: proc() -> bool  ---                             // Check if window is currently minimized
// 	IsWindowMaximized        :: proc() -> bool  ---                             // Check if window is currently maximized
// 	IsWindowFocused          :: proc() -> bool  ---                             // Check if window is currently focused
// 	IsWindowResized          :: proc() -> bool  ---                             // Check if window has been resized last frame
// 	IsWindowState            :: proc(flags: ConfigFlags) -> bool  ---           // Check if one specific window flag is enabled
// 	SetWindowState           :: proc(flags: ConfigFlags) ---                    // Set window configuration state using flags
// 	ClearWindowState         :: proc(flags: ConfigFlags) ---                    // Clear window configuration state flags
// 	ToggleFullscreen         :: proc() ---                                      // Toggle window state: fullscreen/windowed
// 	ToggleBorderlessWindowed :: proc() ---                                      // Toggle window state: borderless windowed
// 	MaximizeWindow           :: proc() ---                                      // Set window state: maximized, if resizable
// 	MinimizeWindow           :: proc() ---                                      // Set window state: minimized, if resizable
// 	RestoreWindow            :: proc() ---                                      // Set window state: not minimized/maximized
// 	SetWindowIcon            :: proc(image: Image) ---                          // Set icon for window (single image, RGBA 32bit,)
// 	SetWindowIcons           :: proc(images: [^]Image, count: c.int) ---        // Set icon for window (multiple images, RGBA 32bit,)
// 	SetWindowTitle           :: proc(title: cstring) ---                        // Set title for window
// }