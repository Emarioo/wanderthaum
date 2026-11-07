package graphics


RenderBackend :: enum {
    OPENGL,
    VULKAN
}

GraphicsState :: struct {
    renderBackend: RenderBackend,
    vulkanBackend: VulkanBackend,
}

