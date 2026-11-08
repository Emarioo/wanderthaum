package graphics

import gl "vendor:OpenGL"
import vk "vendor:vulkan"

import "./shaderc"
import "core:dynlib"

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
                
            vk.DeviceWaitIdle(backend.device)

            vk.DestroyCommandPool(backend.device, backend.commandPool, nil)

            for framebuffer in backend.swapchainFramebuffers {
                vk.DestroyFramebuffer(backend.device, framebuffer, nil)
            }
            for image in backend.imageViews {
                vk.DestroyImageView(backend.device, image, nil)
            }
            for image in backend.images {
                vk.DestroyImage(backend.device, image, nil)
            }
            vk.DestroySwapchainKHR(backend.device, backend.swapchain, nil)


            // vk.DestroyBuffer(backend.device, backend.vertexBuffer, nil);
            // vk.FreeMemory(backend.device, backend.vertexBufferMemory, nil);

            vk.DestroyPipeline(backend.device, backend.graphicsPipeline, nil)
            vk.DestroyPipelineLayout(backend.device, backend.pipelineLayout, nil)

            vk.DestroyRenderPass(backend.device, backend.renderPass, nil)
            
            // @TODO Destroy array of these properly
            for i in 0..<MAX_FRAMES_IN_FLIGHT {
                vk.DestroySemaphore(backend.device, backend.sem_imageAvailable[i], nil)
                vk.DestroySemaphore(backend.device, backend.sem_renderFinished[i], nil)
                vk.DestroyFence(backend.device, backend.fence_inFlight[i], nil)
            }

            // vk.DestroyShaderModule(backend.device, backend.vert_shader, nil)
            // vk.DestroyShaderModule(backend.device, backend.frag_shader, nil)

            vk.DestroyDevice(backend.device, nil)
            vk.DestroySurfaceKHR(backend.instance, backend.surface, nil)
            vk.DestroyInstance(backend.instance, nil)

            dynlib.unload_library(backend.vulkan_dll)

            shaderc.compiler_release(backend.compiler)

            backend^ = {}
    }

}
