/*
    odin run src/vulkantest
    odin build src/vulkantest
*/

package vulkantest

import "core:fmt"
import "core:strings"
import "core:time"
import "core:os"
import "core:os/os2"
import "core:dynlib"
import "base:runtime"
import "core:c"

import vk "vendor:vulkan"
import "vendor:glfw"

import "shaderc"

MAX_FRAMES_IN_FLIGHT :: 2

State :: struct {
    window: glfw.WindowHandle,
    width: i32,
    height: i32,

    appInfo: vk.ApplicationInfo,
    instance: vk.Instance,

    physicalDevice: vk.PhysicalDevice,
    graphics_queueFamilyIndex: u32,
    present_queueFamilyIndex: u32,

    device: vk.Device,
    graphicsQueue: vk.Queue,
    surface: vk.SurfaceKHR,

    capabilities: vk.SurfaceCapabilitiesKHR,
    surfaceFormat: vk.SurfaceFormatKHR,
    presentMode: vk.PresentModeKHR,
    
    swapchain: vk.SwapchainKHR,
    extent: vk.Extent2D,
    imageCount: u32,
    images: []vk.Image,
    imageViews: []vk.ImageView,
    swapchainFramebuffers: []vk.Framebuffer,

    vert_shader: vk.ShaderModule,
    frag_shader: vk.ShaderModule,

    pipelineLayout: vk.PipelineLayout,
    renderPass: vk.RenderPass,
    graphicsPipeline: vk.Pipeline,

    commandPool: vk.CommandPool,
    commandBuffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,

    sem_imageAvailable: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    sem_renderFinished: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    fence_inFlight: [MAX_FRAMES_IN_FLIGHT]vk.Fence,

    frame_resized: bool,


    vertex_data: []f32,
    vertexBindingDescription: vk.VertexInputBindingDescription,
    vertexAttributeDescrptions: [2]vk.VertexInputAttributeDescription,
}

check_error :: proc (err: vk.Result, msg: string) {
    if err != .SUCCESS {
        fmt.println(msg, err)
        os.exit(1)
    }
}

main :: proc () {
    fmt.println("Start");

    state: State
    
    glfw.Init()


    when ODIN_OS == .Windows {
        args := []string{
            "python",
            "src/vulkantest/fix_shaders.py",
        }
    } else {
        args := []string{
            "python3",
            "src/vulkantest/fix_shaders.py",
        }
    }

    handle, err := os2.process_start(
        os2.Process_Desc{
            working_dir = "",
            command = args,
            env =  []string{},
            stderr = os2.stderr,
            stdout = os2.stdout,
            stdin = os2.stdin,
        }
    )
    if err == os2.ERROR_NONE {
        state: os2.Process_State
        state, err = os2.process_wait(handle)
        err = os2.process_close(handle)
        if err != os2.ERROR_NONE {
            fmt.printfln("process_close: %v", err)
        }
    } else {
        fmt.printfln("process_start: %v", err)
    }

    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);
    // glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE);
    
    state.width = 800
    state.height = 600
    state.window = glfw.CreateWindow(state.width, state.height, cstring("vulkantest"), nil, nil)
    
    glfw.SetWindowUserPointer(state.window, &state)
    glfw.SwapInterval(0)

    glfw.SetFramebufferSizeCallback(state.window, FrameBufferResize)

    // @TODO Find linux lib
    path := "vulkan-1.dll"
    vulkan_dll, ok_load := dynlib.load_library(path)
    if !ok_load {
        fmt.printfln("Could not load %v", path)
        os.exit(1)
    }

    funcname := "vkGetInstanceProcAddr"
    proc_loader, ok_func := dynlib.symbol_address(vulkan_dll, funcname)
    if !ok_func {
        fmt.printfln("Could not get %v", funcname)
        os.exit(1)
    }

    vk.load_proc_addresses_global(proc_loader)

    state.appInfo = {
        sType = vk.StructureType.APPLICATION_INFO,
        pApplicationName = cstring("Vulkan Test"),
        applicationVersion = vk.MAKE_VERSION(1,0,0),
        pEngineName = cstring("No Engine"),
        engineVersion = vk.MAKE_VERSION(1,0,0),
        apiVersion = vk.API_VERSION_1_0,
    }

    extensions := glfw.GetRequiredInstanceExtensions()

    // @TODO Check that extensions are supported

    createInfo: vk.InstanceCreateInfo = {
        sType = vk.StructureType.INSTANCE_CREATE_INFO,
        pApplicationInfo = &state.appInfo,
        enabledExtensionCount = cast(u32)len(extensions),
        ppEnabledExtensionNames = raw_data(extensions),
        enabledLayerCount = 0,
    }



    res: vk.Result
    res = vk.CreateInstance(&createInfo, nil, &state.instance)
    if res != .SUCCESS {
        fmt.printfln("Failed creating vk instance")
        os.exit(1)
    }

    res = glfw.CreateWindowSurface(state.instance, state.window, nil, &state.surface)
    check_error(res, "Could not create surface")

    vk.load_proc_addresses_instance(state.instance)

    pick_device(&state)

    load_shader(&state)

    // @TODO Calculate extent from capabilities. in case capabilities.currentExtend.width is MAXUINT?
    create_swapchain(&state)
    



    {
        sem_info : vk.SemaphoreCreateInfo = {
            sType = .SEMAPHORE_CREATE_INFO,
        }
        fence_info : vk.FenceCreateInfo = {
            sType = .FENCE_CREATE_INFO,
            flags = { .SIGNALED },
        }
        for i in 0..<MAX_FRAMES_IN_FLIGHT {
            res = vk.CreateSemaphore(state.device, &sem_info, nil, &state.sem_imageAvailable[i])
            check_error(res, "sem failed1")
            res = vk.CreateSemaphore(state.device, &sem_info, nil, &state.sem_renderFinished[i])
            check_error(res, "sem failed2")
            res = vk.CreateFence(state.device, &fence_info, nil, &state.fence_inFlight[i])
            check_error(res, "fence failed")
        }
    }

    _vertex_data := [?]f32 {
        0.0, -0.5, 1.0, 0.0, 0.0,
        0.5, 0.5, 0.0, 1.0, 0.0,
        -0.5, 0.5, 0.0, 0.0, 1.0,
    };
    state.vertex_data = _vertex_data[:]

    // fmt.println("Capabilities", state.capabilities)
    // fmt.println("Formats", state.formats)
    // fmt.println("Modes", state.presentModes)

    currentFrame : u32
    for !glfw.WindowShouldClose(state.window) {
        glfw.PollEvents()

        vk.WaitForFences(state.device, 1, &state.fence_inFlight[currentFrame], true, cast(u64)-1)

        imageIndex: u32
        res = vk.AcquireNextImageKHR(state.device, state.swapchain, cast(u64)-1, state.sem_imageAvailable[currentFrame], 0, &imageIndex)
        if res == .ERROR_OUT_OF_DATE_KHR {
            fmt.println("Resized1")
            recreate_swapchain(&state)
            continue
        } else if (res != .SUCCESS && res != .SUBOPTIMAL_KHR) {
            check_error(res, "failed acquire next image")
        }
        vk.ResetFences(state.device, 1, &state.fence_inFlight[currentFrame])

        vk.ResetCommandBuffer(state.commandBuffers[currentFrame], {})

        record_command_buffer(&state, state.commandBuffers[currentFrame], imageIndex)

        waitStages: [1]vk.PipelineStageFlags = { { .COLOR_ATTACHMENT_OUTPUT } }
        submitInfo: vk.SubmitInfo = {
            sType = .SUBMIT_INFO,
            waitSemaphoreCount = 1,
            pWaitSemaphores = &state.sem_imageAvailable[currentFrame],
            pWaitDstStageMask = &waitStages[0],
            commandBufferCount = 1,
            pCommandBuffers = &state.commandBuffers[currentFrame],
            signalSemaphoreCount = 1,
            pSignalSemaphores = &state.sem_renderFinished[currentFrame],
        }

        res = vk.QueueSubmit(state.graphicsQueue, 1, &submitInfo, state.fence_inFlight[currentFrame])
        check_error(res, "failed submit queue")

        presentInfo: vk.PresentInfoKHR = {
            sType = .PRESENT_INFO_KHR,
            waitSemaphoreCount = 1,
            pWaitSemaphores = &state.sem_renderFinished[currentFrame],
            swapchainCount = 1,
            pSwapchains = &state.swapchain,
            pImageIndices = &imageIndex,
            pResults = nil, // optional
        }

        // @TODO Present and graphics queue are assumed to be the same. (a problem?)
        res = vk.QueuePresentKHR(state.graphicsQueue, &presentInfo)
        if res == .ERROR_OUT_OF_DATE_KHR || state.frame_resized {
            // @TODO I don't think the resize is working. The triangle looks pixelated when scaled up.
            //   Do we render once and then continously fail? try make moving triangle to see if we render.
            fmt.println("Resized")
            state.frame_resized = false
            recreate_swapchain(&state)
        } else if (res != .SUCCESS && res != .SUBOPTIMAL_KHR) {
            check_error(res, "failed acquire next image")
        }

        currentFrame = (currentFrame + 1) % MAX_FRAMES_IN_FLIGHT

        time.sleep(16 * time.Millisecond)

    }

    vk.DeviceWaitIdle(state.device)

    vk.DestroyCommandPool(state.device, state.commandPool, nil)

    for framebuffer in state.swapchainFramebuffers {
        vk.DestroyFramebuffer(state.device, framebuffer, nil)
    }
    for image in state.imageViews {
        vk.DestroyImageView(state.device, image, nil)
    }
    // @TODO Destroy images?
    vk.DestroySwapchainKHR(state.device, state.swapchain, nil)

    vk.DestroyPipeline(state.device, state.graphicsPipeline, nil)
    vk.DestroyPipelineLayout(state.device, state.pipelineLayout, nil)

    vk.DestroyRenderPass(state.device, state.renderPass, nil)
    
    // @TODO Destroy array of these properly
    // vk.DestroySemaphore(state.device, state.sem_imageAvailable, nil)
    // vk.DestroySemaphore(state.device, state.sem_renderFinished, nil)
    // vk.DestroyFence(state.device, state.fence_inFlight, nil)

    vk.DestroyShaderModule(state.device, state.vert_shader, nil)
    vk.DestroyShaderModule(state.device, state.frag_shader, nil)

    vk.DestroyDevice(state.device, nil)
    vk.DestroySurfaceKHR(state.instance, state.surface, nil)
    vk.DestroyInstance(state.instance, nil)

    dynlib.unload_library(vulkan_dll)
    
    fmt.println("Finish");
}

make_vertex_buffer :: proc (state: ^State) {
    state.vertexBindingDescription.binding = 0
    state.vertexBindingDescription.stride = 5*4
    state.vertexBindingDescription.inputRate = .VERTEX

    state.vertexAttributeDescrptions[0].binding = 0
    state.vertexAttributeDescrptions[0].location = 0
    state.vertexAttributeDescrptions[0].format = .R32G32_SFLOAT
    state.vertexAttributeDescrptions[0].offset = 0
    state.vertexAttributeDescrptions[1].binding = 0
    state.vertexAttributeDescrptions[1].location = 1
    state.vertexAttributeDescrptions[1].format = .R32G32B32_SFLOAT
    state.vertexAttributeDescrptions[1].offset = 12

}

FrameBufferResize :: proc "c" (window: glfw.WindowHandle, width, height: c.int) {
    state := cast(^State)glfw.GetWindowUserPointer(window)

    state.frame_resized = true
}

load_shader :: proc (state: ^State) {
    res: vk.Result

    
    {
        vert_data, ok := os.read_entire_file("vert.spv")
        if !ok {
            fmt.printfln("Could not read vert.spv")
            // return .file_not_found
            return
        }
        defer delete(vert_data)
        createInfo: vk.ShaderModuleCreateInfo = {
            sType = .SHADER_MODULE_CREATE_INFO,
            codeSize = len(vert_data),
            pCode = cast(^u32)raw_data(vert_data),
        }
        
        res = vk.CreateShaderModule(state.device, &createInfo, nil, &state.vert_shader)
        check_error(res, "Failed creating vert shader module")
    }
    {
        frag_data, ok := os.read_entire_file("frag.spv")
        if !ok {
            fmt.printfln("Could not read frag.spv")
            return
        }
        defer delete(frag_data)
        createInfo: vk.ShaderModuleCreateInfo
        createInfo.sType = .SHADER_MODULE_CREATE_INFO
        createInfo.codeSize = len(frag_data)
        createInfo.pCode = cast(^u32)raw_data(frag_data)

        res = vk.CreateShaderModule(state.device, &createInfo, nil, &state.frag_shader)
        check_error(res, "Failed creating frag shader module")
    }
    vertPipelineStageInfo: vk.PipelineShaderStageCreateInfo = {
        sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage = { .VERTEX },
        module = state.vert_shader,
        pName = "main",
    }

    fragPipelineStageInfo: vk.PipelineShaderStageCreateInfo = {
        sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage = { .FRAGMENT },
        module = state.frag_shader,
        pName = "main",
    }


    dynamicStates: [2]vk.DynamicState = {
        .VIEWPORT,
        .SCISSOR,
    }
    
    pipelineDynamicInfo: vk.PipelineDynamicStateCreateInfo = {
        sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        dynamicStateCount = len(dynamicStates),
        pDynamicStates = raw_data(&dynamicStates),
    }

    vertexInputInfo: vk.PipelineVertexInputStateCreateInfo = {
        sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount = 0,
        pVertexBindingDescriptions = nil,
        vertexAttributeDescriptionCount = 0,
        pVertexAttributeDescriptions = nil,
    }

    inputAssembly: vk.PipelineInputAssemblyStateCreateInfo = {
        sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology = .TRIANGLE_LIST,
        primitiveRestartEnable = false,
    }

    viewport: vk.Viewport = {
        x = 0.0,
        y = 0.0,
        width = cast(f32)state.extent.width,
        height = cast(f32)state.extent.height,
        minDepth = 0.0,
        maxDepth = 1.0,
    }

    scissor: vk.Rect2D = {
        offset = {0, 0},
        extent = state.extent,
    }

    viewportState: vk.PipelineViewportStateCreateInfo = {
        sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount = 1,
        pViewports = &viewport,
        scissorCount = 1,
        pScissors = &scissor,
    }
    
    rasterizer: vk.PipelineRasterizationStateCreateInfo = {
        sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        depthClampEnable = false,
        rasterizerDiscardEnable = false,
        polygonMode = .FILL,
        lineWidth = 1.0,
        cullMode = { .BACK },
        frontFace = .CLOCKWISE,
        depthBiasEnable = false,
    }

    multisampling: vk.PipelineMultisampleStateCreateInfo = {
        sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        sampleShadingEnable = false,
        rasterizationSamples = { ._1 },
        minSampleShading = 1.0,
        pSampleMask = nil,
        alphaToCoverageEnable = false,
        alphaToOneEnable = false,
    }
 
    colorBlendAttachment: vk.PipelineColorBlendAttachmentState = {
        colorWriteMask = { .R, .G, .B, .A },
        blendEnable = true,
        srcColorBlendFactor = .SRC_ALPHA,
        dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
        colorBlendOp = .ADD,
        srcAlphaBlendFactor = .ONE,
        dstAlphaBlendFactor = .ZERO,
        alphaBlendOp = .ADD,
    }

    colorBlending: vk.PipelineColorBlendStateCreateInfo = {
        sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        logicOpEnable = false, // other fields not necessary since it's false?
        logicOp = .COPY,
        attachmentCount = 1,
        pAttachments = &colorBlendAttachment,
        blendConstants = {
            0.0, 0.0, 0.0, 0.0,
        }
    }

    pipelineLayoutInfo: vk.PipelineLayoutCreateInfo = {
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = 0,
        pSetLayouts = nil,
        pushConstantRangeCount = 0,
        pPushConstantRanges = nil,
    }

    res = vk.CreatePipelineLayout(state.device, &pipelineLayoutInfo, nil, &state.pipelineLayout)
    check_error(res, "failed to create pipeline layout!")
    
    colorAttachment: vk.AttachmentDescription = {
        format = state.surfaceFormat.format,
        samples = { ._1 },
        loadOp = .CLEAR,
        storeOp = .STORE,
        stencilLoadOp = .DONT_CARE,
        stencilStoreOp = .DONT_CARE,
        initialLayout = .UNDEFINED,
        finalLayout = .PRESENT_SRC_KHR,
    }

    colorAttachmentRef: vk.AttachmentReference = {
        attachment = 0,
        layout = .COLOR_ATTACHMENT_OPTIMAL,
    }

    subpass: vk.SubpassDescription = {
        pipelineBindPoint = .GRAPHICS,
        colorAttachmentCount = 1,
        pColorAttachments = &colorAttachmentRef,
    }

    dependency: vk.SubpassDependency = {
        srcSubpass = vk.SUBPASS_EXTERNAL,
        dstSubpass = 0,
        srcStageMask = { .COLOR_ATTACHMENT_OUTPUT },
        srcAccessMask = {},
        dstStageMask = { .COLOR_ATTACHMENT_OUTPUT },
        dstAccessMask = { .COLOR_ATTACHMENT_WRITE },
    }

    renderPassInfo: vk.RenderPassCreateInfo = {
        sType = .RENDER_PASS_CREATE_INFO,
        attachmentCount = 1,
        pAttachments = &colorAttachment,
        subpassCount = 1,
        pSubpasses = &subpass,
        dependencyCount = 1,
        pDependencies = &dependency,
    }

    res = vk.CreateRenderPass(state.device, &renderPassInfo, nil, &state.renderPass)
    check_error(res, "failed to create render pass!")

    
    shaderStages: [2]vk.PipelineShaderStageCreateInfo = {
        vertPipelineStageInfo,
        fragPipelineStageInfo
    }

    pipelineInfo: vk.GraphicsPipelineCreateInfo = {
        sType = .GRAPHICS_PIPELINE_CREATE_INFO,
        stageCount = 2,
        pStages = &shaderStages[0],
        pVertexInputState = &vertexInputInfo,
        pInputAssemblyState = &inputAssembly,
        pViewportState = &viewportState,
        pRasterizationState = &rasterizer,
        pMultisampleState = &multisampling,
        pDepthStencilState = nil,
        pColorBlendState = &colorBlending,
        pDynamicState = &pipelineDynamicInfo,

        layout = state.pipelineLayout,
        renderPass = state.renderPass,
        subpass = 0,
        basePipelineHandle = 0,
        basePipelineIndex = -1,
    }
    
    res = vk.CreateGraphicsPipelines(state.device, 0, 1, &pipelineInfo, nil, &state.graphicsPipeline)
    check_error(res, "Failed creating graphics pipeline")

     
    poolInfo: vk.CommandPoolCreateInfo = {
        sType = .COMMAND_POOL_CREATE_INFO,
        flags = { .RESET_COMMAND_BUFFER },
        queueFamilyIndex = state.graphics_queueFamilyIndex,
    }

    res = vk.CreateCommandPool(state.device, &poolInfo, nil, &state.commandPool)
    check_error(res, "failed to create command pool")

    allocInfo: vk.CommandBufferAllocateInfo = {
        sType = .COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool = state.commandPool,
        level = .PRIMARY,
        commandBufferCount = MAX_FRAMES_IN_FLIGHT,
    }

    res = vk.AllocateCommandBuffers(state.device, &allocInfo, &state.commandBuffers[0])
    check_error(res, "failed to allocate command buffers!")

}

record_command_buffer :: proc (state: ^State, commandBuffer: vk.CommandBuffer, imageIndex: u32) {
    res: vk.Result

    beginInfo: vk.CommandBufferBeginInfo = {
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = {},
        pInheritanceInfo = nil,
    }

    res = vk.BeginCommandBuffer(commandBuffer, &beginInfo)
    check_error(res, "failed to begin command!")

    renderPassInfo: vk.RenderPassBeginInfo = {
        sType = .RENDER_PASS_BEGIN_INFO,
        renderPass = state.renderPass,
        framebuffer = state.swapchainFramebuffers[imageIndex],
        renderArea = {
            offset = {0, 0},
            extent = state.extent,
        },
    }

    clearColor: vk.ClearValue = { color = { float32 = { 0.0, 0.0, 0.0, 1.0 }}};
    renderPassInfo.clearValueCount = 1;
    renderPassInfo.pClearValues = &clearColor;
    
    vk.CmdBeginRenderPass(commandBuffer, &renderPassInfo, .INLINE);

    vk.CmdBindPipeline(commandBuffer, .GRAPHICS, state.graphicsPipeline);

    viewport: vk.Viewport = {
        x = 0.0,
        y = 0.0,
        width = cast(f32)(state.extent.width),
        height = cast(f32)(state.extent.height),
        minDepth = 0.0,
        maxDepth = 1.0,
    }
    vk.CmdSetViewport(commandBuffer, 0, 1, &viewport);

    scissor: vk.Rect2D = {
        offset = {0, 0},
        extent = state.extent,
    }
    vk.CmdSetScissor(commandBuffer, 0, 1, &scissor);

    vk.CmdDraw(commandBuffer, 3, 1, 0, 0)

    vk.CmdEndRenderPass(commandBuffer)

    res = vk.EndCommandBuffer(commandBuffer)
    check_error(res, "failed to record command buffer")
}

recreate_swapchain :: proc (state: ^State) {
    // @TODO Handle minimize window, https://vulkan-tutorial.com/Drawing_a_triangle/Swap_chain_recreation

    vk.DeviceWaitIdle(state.device);

    // cleanup swapchain

    for framebuffer in state.swapchainFramebuffers {
        vk.DestroyFramebuffer(state.device, framebuffer, nil)
    }
    for image in state.imageViews {
        vk.DestroyImageView(state.device, image, nil)
    }
    vk.DestroySwapchainKHR(state.device, state.swapchain, nil)

    // make swapchain
    
    create_swapchain(state)
}

create_swapchain :: proc (state: ^State) {
    res: vk.Result
    state.imageCount = state.capabilities.minImageCount + 1
    if state.capabilities.maxImageCount > 0 && state.imageCount > state.capabilities.maxImageCount {
        state.imageCount = state.capabilities.maxImageCount
    }

    state.extent = state.capabilities.currentExtent

    createInfo: vk.SwapchainCreateInfoKHR = {
        sType = .SWAPCHAIN_CREATE_INFO_KHR,
        surface = state.surface,
        minImageCount = state.imageCount,
        imageFormat = state.surfaceFormat.format,
        imageColorSpace = state.surfaceFormat.colorSpace,
        imageExtent = state.extent,
        imageArrayLayers = 1,
        imageUsage = { .COLOR_ATTACHMENT },
    }
    
    if state.present_queueFamilyIndex != state.graphics_queueFamilyIndex {
        fmt.println("we assume graphics, present queue family index, this is not the case")
        os.exit(1)
    }
    createInfo.imageSharingMode = .EXCLUSIVE
    // set queueFamilyINdexCount and pQueueFamilyIndices otherwise

    createInfo.preTransform = state.capabilities.currentTransform
    createInfo.compositeAlpha = { .OPAQUE }  // @TODO Is this where we can specify alpha and have transparent windows, like transparent background ofr code editors or game launcher with rounded edges?

    createInfo.presentMode = state.presentMode
    createInfo.clipped = true
    createInfo.oldSwapchain = cast(vk.SwapchainKHR)0

    res = vk.CreateSwapchainKHR(state.device, &createInfo, nil, &state.swapchain)
    check_error(res, "could not make swapchain")


    vk.GetSwapchainImagesKHR(state.device, state.swapchain, &state.imageCount, nil)
    state.images = make([]vk.Image, state.imageCount)
    vk.GetSwapchainImagesKHR(state.device, state.swapchain, &state.imageCount, raw_data(state.images))


    state.imageViews = make([]vk.ImageView, len(state.images))

    for &image, index in state.imageViews {
        createInfo: vk.ImageViewCreateInfo = {
            sType = .IMAGE_VIEW_CREATE_INFO,
            image = state.images[index],
            viewType = .D2,
            format = state.surfaceFormat.format,
            components = {
                r = .IDENTITY,
                g = .IDENTITY,
                b = .IDENTITY,
                a = .IDENTITY,
            },
            subresourceRange = {
                aspectMask = { .COLOR },
                baseMipLevel = 0,
                levelCount = 1,
                baseArrayLayer = 0,
                layerCount = 1,
            },
        }

        res = vk.CreateImageView(state.device, &createInfo, nil, &image)
        check_error(res, "Failed making image view")

    }

    state.swapchainFramebuffers = make([]vk.Framebuffer, len(state.imageViews))
    for view, i in state.imageViews {
        attachments: []vk.ImageView = {
            view
        }
        framebufferInfo: vk.FramebufferCreateInfo = {
            sType = .FRAMEBUFFER_CREATE_INFO,
            renderPass = state.renderPass,
            attachmentCount = 1,
            pAttachments = &attachments[0],
            width = state.extent.width,
            height = state.extent.height,
            layers = 1,
        }

        res = vk.CreateFramebuffer(state.device, &framebufferInfo, nil, &state.swapchainFramebuffers[i])
        check_error(res, "failed to create framebuffer!")
    }
}

pick_device :: proc (state: ^State) {
    res: vk.Result

    count: u32
    vk.EnumeratePhysicalDevices(state.instance, &count, nil)
    // check_error(res, "Bad enumerate")
    devices := make([]vk.PhysicalDevice, count)
    defer delete(devices)
    vk.EnumeratePhysicalDevices(state.instance, &count, raw_data(devices))
    // check_error(res, "Bad enumerate")

    
    best_device: vk.PhysicalDevice = cast(vk.PhysicalDevice)nil
    best_properties: vk.PhysicalDeviceProperties

    for device in devices {
        properties: vk.PhysicalDeviceProperties
        features:   vk.PhysicalDeviceFeatures
        vk.GetPhysicalDeviceProperties(device, &properties)
        vk.GetPhysicalDeviceFeatures(device, &features)

        extensionCount: u32
        vk.EnumerateDeviceExtensionProperties(device, nil, &extensionCount, nil)
        extensions := make([]vk.ExtensionProperties, extensionCount)
        defer delete(extensions)
        vk.EnumerateDeviceExtensionProperties(device, nil, &extensionCount, raw_data(extensions))
        
        usable: bool = false
        for &ext in extensions {
            name := cstring(transmute([^]u8)(&ext.extensionName))
            if name == vk.KHR_SWAPCHAIN_EXTENSION_NAME {
                usable = true
            }
        }

        formatCount: u32
        vk.GetPhysicalDeviceSurfaceFormatsKHR(device, state.surface, &formatCount, nil)
        if formatCount == 0 {
            continue
        }
        modeCount: u32
        vk.GetPhysicalDeviceSurfacePresentModesKHR(device, state.surface, &modeCount, nil)
        if modeCount == 0 {
            continue
        }
        if !usable {
            continue
        }

        // fmt.printfln("Device N: %v %v", properties, features)
        if properties.deviceType == .DISCRETE_GPU {
            best_device = device
            best_properties = properties
            break
        } else if properties.deviceType == .INTEGRATED_GPU && best_device != nil && best_properties.deviceType != .DISCRETE_GPU {
            best_device = device
            best_properties = properties
        }
    }

    state.physicalDevice = best_device

    formats: []vk.SurfaceFormatKHR
    presentModes: []vk.PresentModeKHR
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(state.physicalDevice, state.surface, &state.capabilities)

    formatCount: u32
    vk.GetPhysicalDeviceSurfaceFormatsKHR(state.physicalDevice, state.surface, &formatCount, nil)
    formats = make([]vk.SurfaceFormatKHR, formatCount)
    defer delete(formats)
    vk.GetPhysicalDeviceSurfaceFormatsKHR(state.physicalDevice, state.surface, &formatCount, raw_data(formats))
    
    modeCount: u32
    vk.GetPhysicalDeviceSurfacePresentModesKHR(state.physicalDevice, state.surface, &modeCount, nil)
    presentModes = make([]vk.PresentModeKHR, modeCount)
    defer delete(presentModes)
    vk.GetPhysicalDeviceSurfacePresentModesKHR(state.physicalDevice, state.surface, &modeCount, raw_data(presentModes))
    
    state.surfaceFormat = formats[0]
    for format in formats {
        if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
            state.surfaceFormat = format
            break
        }
    }
    
    state.presentMode = .FIFO
    for mode in presentModes {
        if mode == .MAILBOX {
            state.presentMode = mode
            break
        }
    }



    count = 0
    vk.GetPhysicalDeviceQueueFamilyProperties(state.physicalDevice, &count, nil)
    queueFamilies := make([]vk.QueueFamilyProperties, count)
    defer delete(queueFamilies)
    vk.GetPhysicalDeviceQueueFamilyProperties(state.physicalDevice, &count, raw_data(queueFamilies))


    for family, i in queueFamilies {
        // fmt.printfln("%v", family)
        if .GRAPHICS in family.queueFlags {
            // @TODO Can multiple families have GRAPHICS? (mine does not, AMD Radeon 7900 XT)
            state.graphics_queueFamilyIndex = cast(u32)i
            break
        }
    }
    for family, i in queueFamilies {
        presentSupport: b32
        res = vk.GetPhysicalDeviceSurfaceSupportKHR(state.physicalDevice, cast(u32)i, state.surface, &presentSupport)
        check_error(res, "ERROR: GetPhysicalDeviceSurfaceSupportKHR")
        if presentSupport {
            state.present_queueFamilyIndex = cast(u32)i
            break
        }
    }

    if state.present_queueFamilyIndex != state.graphics_queueFamilyIndex {
        fmt.println("PRESENT and GRAPHICS QUEUE FAMILY are different, implement this!")
        os.exit(1)
    }

    prio: f32 = 1.0
    queueCreateInfo: vk.DeviceQueueCreateInfo = {
        sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
        queueFamilyIndex = state.graphics_queueFamilyIndex,
        queueCount = 1,
        pQueuePriorities = &prio,
    }
    
    deviceFeatures: vk.PhysicalDeviceFeatures
    // don't need anything special

    extensions: []cstring = {
        vk.KHR_SWAPCHAIN_EXTENSION_NAME,
    }

    createInfo: vk.DeviceCreateInfo = {
        sType = vk.StructureType.DEVICE_CREATE_INFO,
        pQueueCreateInfos = &queueCreateInfo,
        queueCreateInfoCount = 1,
        pEnabledFeatures = &deviceFeatures,
        enabledExtensionCount = cast(u32)len(extensions),
        ppEnabledExtensionNames = raw_data(extensions),
    }

    res = vk.CreateDevice(state.physicalDevice, &createInfo, nil, &state.device)
    check_error(res, "Could not create device")

    // @TODO Do we want to get more queues, not use index 0
    vk.GetDeviceQueue(state.device, state.graphics_queueFamilyIndex, 0, &state.graphicsQueue)
}