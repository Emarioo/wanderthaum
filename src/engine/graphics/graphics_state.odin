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
            for view in backend.depthImageViews {
                vk.DestroyImageView(backend.device, view, nil)
            }
            for i in 0..<len(backend.depthImages) {
                vk.DestroyImage(backend.device, backend.depthImages[i], nil)
                vk.FreeMemory(backend.device, backend.depthMemories[i], nil)
            }
            for image in backend.imageViews {
                vk.DestroyImageView(backend.device, image, nil)
            }
            // @IMPORTANT backend.images (swapchain images) should not be destroyed by us.
            //    Something else handles them.
            vk.DestroySwapchainKHR(backend.device, backend.swapchain, nil)

            delete(backend.depthImages)
            delete(backend.depthMemories)
            delete(backend.depthImageViews)
            
            delete(backend.images)
            delete(backend.imageViews)
            delete(backend.swapchainFramebuffers)
         

            destroy_pipeline :: proc (device: vk.Device, pipeline: ^vulkan_Pipeline) {
                if pipeline.graphicsPipeline != 0 {
                    vk.DestroyPipeline(device, pipeline.graphicsPipeline, nil)
                    vk.DestroyPipelineLayout(device, pipeline.pipelineLayout, nil)
                }

            }
            destroy_render_pass :: proc (device: vk.Device, renderPass: ^vulkan_RenderPass) {
                if renderPass.renderPass != 0 {
                    vk.DestroyRenderPass(device, renderPass.renderPass, nil)
                }
            }

            destroy_pipeline(backend.device, &backend.pipeline_rect)
            destroy_pipeline(backend.device, &backend.pipeline_object)
            destroy_pipeline(backend.device, &backend.pipeline_wireframe)
            destroy_render_pass(backend.device, &backend.default_renderPass)
            
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
