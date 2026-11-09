package graphics

import gl "vendor:OpenGL"
import vk "vendor:vulkan"

import "./shaderc"
import "core:dynlib"
import "core:fmt"

RenderBackend :: enum {
    OPENGL,
    VULKAN
}

GraphicsState :: struct {
    renderBackend: RenderBackend,
    vulkanBackend: VulkanBackend,
}


destroy_all_resources :: proc (state: ^GraphicsState) {

    switch (state.renderBackend) {
        case .OPENGL:

        case .VULKAN:
            backend := &state.vulkanBackend
            if backend.device == nil {
                return
            }
            
            vk.DeviceWaitIdle(backend.device)

            vk.DestroyCommandPool(backend.device, backend.commandPool, nil)

            for framebuffer in backend.swapchainFramebuffers {
                vk.DestroyFramebuffer(backend.device, framebuffer, nil)
            }
            for image in backend.imageViews {
                vk.DestroyImageView(backend.device, image, nil)
            }
            // @IMPORTANT backend.images (swapchain images) should not be destroyed by us.
            //    Something else handles them.

            vk.DestroySwapchainKHR(backend.device, backend.swapchain, nil)

            vk.DestroyPipeline(backend.device, backend.graphicsPipeline, nil)
            vk.DestroyPipelineLayout(backend.device, backend.pipelineLayout, nil)

            vk.DestroyRenderPass(backend.device, backend.renderPass, nil)
            
            for i in 0..<MAX_FRAMES_IN_FLIGHT {
                vk.DestroySemaphore(backend.device, backend.sem_imageAvailable[i], nil)
                vk.DestroySemaphore(backend.device, backend.sem_renderFinished[i], nil)
                vk.DestroyFence(backend.device, backend.fence_inFlight[i], nil)
            }

            vk.DestroyDevice(backend.device, nil)
            vk.DestroySurfaceKHR(backend.instance, backend.surface, nil)
            vk.DestroyInstance(backend.instance, nil)

            dynlib.unload_library(backend.vulkan_dll)

            shaderc.compiler_release(backend.compiler)

            backend^ = {}
    }

}
