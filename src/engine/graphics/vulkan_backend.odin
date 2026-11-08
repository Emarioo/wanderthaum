package graphics


import "core:fmt"
import "core:strings"
import "core:time"
import "core:os"
import "core:dynlib"
import "base:runtime"
import "base:intrinsics"
import "core:c"

import vk "vendor:vulkan"
import "vendor:glfw"

MAX_FRAMES_IN_FLIGHT :: 2

// @NOCHECKIN Move elsewhere
Rect_Push_Constants :: struct {
    color:  [4]f32,
    window: [2]f32,
    pos:    [2]f32,
    size:   [2]f32,
}


VulkanBackend :: struct {
    vulkan_dll: dynlib.Library,
    proc_loader: rawptr,

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

    made_pipeline: bool,

    pipelineLayout: vk.PipelineLayout,
    renderPass: vk.RenderPass,
    graphicsPipeline: vk.Pipeline,
    
    commandPool: vk.CommandPool,
    commandBuffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,

    sem_imageAvailable: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    sem_renderFinished: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    fence_inFlight: [MAX_FRAMES_IN_FLIGHT]vk.Fence,

    currentFrame : u32,
    frame_resized: bool,
    
    // vertexBindingDescription: vk.VertexInputBindingDescription,
    // vertexAttributeDescriptions: [2]vk.VertexInputAttributeDescription,
}


check_error :: proc (err: vk.Result, msg: string) {
    if err != .SUCCESS {
        fmt.println(msg, err)
        os.exit(1)
    }
}


checkValidationLayerSupport :: proc () -> bool {
    layerCount: u32;
    vk.EnumerateInstanceLayerProperties(&layerCount, nil);

    availableLayers := make([]vk.LayerProperties, layerCount)
    vk.EnumerateInstanceLayerProperties(&layerCount, raw_data(availableLayers));

    for layerName in validationLayers {
        layerFound := false
        for i in 0..<len(availableLayers) {
            if layerName == cstring(raw_data(&availableLayers[i].layerName)) {
                layerFound = true;
                break;
            }
        }

        if !layerFound {
            return false
        }
    }

    return true;
}

validationLayers : []cstring : {
    "VK_LAYER_KHRONOS_validation"
}

set_vulkan_globals :: proc (backend: ^VulkanBackend) {
    if backend.proc_loader != nil {
        vk.load_proc_addresses_global(backend.proc_loader)
    }
    
    if backend.instance != nil {
        vk.load_proc_addresses_instance(backend.instance)
    }
}

vulkan_init_window :: proc (backend: ^VulkanBackend, width, height: int, title: string) -> glfw.WindowHandle {

    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API);

    cloned_name := strings.clone_to_cstring(title)
    // @TODO Memory leak string

    window := glfw.CreateWindow(cast(c.int)width, cast(c.int)height, cloned_name, nil, nil)

    // @TODO Find linux lib
    path := "vulkan-1.dll"
    did_load: bool
    backend.vulkan_dll, did_load = dynlib.load_library(path)
    if !did_load {
        fmt.printfln("Could not load %v", path)
        os.exit(1)
    }

    funcname := "vkGetInstanceProcAddr"
    found_symbol: bool
    backend.proc_loader, found_symbol = dynlib.symbol_address(backend.vulkan_dll, funcname)
    if !found_symbol {
        fmt.printfln("Could not get %v", funcname)
        os.exit(1)
    }

    vk.load_proc_addresses_global(backend.proc_loader)

    backend.appInfo = {
        sType = vk.StructureType.APPLICATION_INFO,
        pApplicationName = cstring("Wanderthaum"),
        applicationVersion = vk.MAKE_VERSION(1,0,0),
        pEngineName = cstring("No Engine"),
        engineVersion = vk.MAKE_VERSION(1,0,0),
        apiVersion = vk.API_VERSION_1_0,
    }

    extensions := glfw.GetRequiredInstanceExtensions()
    
    // @TODO Check that extensions are supported

    createInfo: vk.InstanceCreateInfo = {
        sType = vk.StructureType.INSTANCE_CREATE_INFO,
        pApplicationInfo = &backend.appInfo,
        enabledExtensionCount = cast(u32)len(extensions),
        ppEnabledExtensionNames = raw_data(extensions),
        // enabledLayerCount = cast(u32)len(validationLayers),
        // ppEnabledLayerNames = raw_data(validationLayers),
    }

    res: vk.Result
    res = vk.CreateInstance(&createInfo, nil, &backend.instance)
    if res != .SUCCESS {
        fmt.printfln("Failed creating vk instance")
        os.exit(1)
    }

    res = glfw.CreateWindowSurface(backend.instance, window, nil, &backend.surface)
    check_error(res, "Could not create surface")

    vk.load_proc_addresses_instance(backend.instance)

    return window
}


vulkan_init_upfront_internals :: proc (backend: ^VulkanBackend) {
    res: vk.Result

    pick_device(backend)
    
    // @TODO Calculate extent from capabilities. in case capabilities.currentExtend.width is MAXUINT?
    create_swapchain(backend)
 
    {
        sem_info : vk.SemaphoreCreateInfo = {
            sType = .SEMAPHORE_CREATE_INFO,
        }
        fence_info : vk.FenceCreateInfo = {
            sType = .FENCE_CREATE_INFO,
            flags = { .SIGNALED },
        }
        for i in 0..<MAX_FRAMES_IN_FLIGHT {
            res = vk.CreateSemaphore(backend.device, &sem_info, nil, &backend.sem_imageAvailable[i])
            check_error(res, "sem failed1")
            res = vk.CreateSemaphore(backend.device, &sem_info, nil, &backend.sem_renderFinished[i])
            check_error(res, "sem failed2")
            res = vk.CreateFence(backend.device, &fence_info, nil, &backend.fence_inFlight[i])
            check_error(res, "fence failed")
        }
    }
   
}







pick_device :: proc (backend: ^VulkanBackend) {
    res: vk.Result

    // Separate this code into
    // - List all devices and pick the best one
    // - Initialize the best device

    count: u32
    res = vk.EnumeratePhysicalDevices(backend.instance, &count, nil)
    check_error(res, "Bad enumerate")
    devices := make([]vk.PhysicalDevice, count)
    defer delete(devices)
    res = vk.EnumeratePhysicalDevices(backend.instance, &count, raw_data(devices))
    check_error(res, "Bad enumerate")

    
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
        
        formatCount: u32
        vk.GetPhysicalDeviceSurfaceFormatsKHR(device, backend.surface, &formatCount, nil)
        modeCount: u32
        vk.GetPhysicalDeviceSurfacePresentModesKHR(device, backend.surface, &modeCount, nil)
        
        usable: bool = false
        for &ext in extensions {
            name := cstring(transmute([^]u8)(&ext.extensionName))
            if name == vk.KHR_SWAPCHAIN_EXTENSION_NAME {
                usable = true
            }
        }

        fmt.println("----------------------------------------")
        fmt.printf("GPU: %s\n", cstring(transmute([^]u8)&properties.deviceName))
        fmt.printf("Vendor ID: 0x%04X\n", properties.vendorID)
        fmt.printf("Device ID: 0x%04X\n", properties.deviceID)
        fmt.printf("API version: %d.%d.%d\n",
            vk.API_VERSION_MAJOR(properties.apiVersion),
            vk.API_VERSION_MINOR(properties.apiVersion),
            vk.API_VERSION_PATCH(properties.apiVersion),
        )
        fmt.printf("Driver version: %d\n", properties.driverVersion)

        switch properties.deviceType {
            case .DISCRETE_GPU:   fmt.println("Type: Discrete GPU")
            case .INTEGRATED_GPU: fmt.println("Type: Integrated GPU")
            case .VIRTUAL_GPU:    fmt.println("Type: Virtual GPU")
            case .CPU:            fmt.println("Type: CPU")
            case .OTHER:          fmt.println("Type: Other")
        }

        fmt.printf("Swapchain extension: %v\n", usable)
        fmt.printf("Surface formats: %d\n", formatCount)
        fmt.printf("Present modes: %d\n", modeCount)


        if formatCount == 0 {
            continue
        }
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
        } else if properties.deviceType == .INTEGRATED_GPU && (best_device == nil || best_properties.deviceType != .DISCRETE_GPU) {
            best_device = device
            best_properties = properties
        }
    }

    if best_device == nil {
        fmt.println("vulkan_backend: Could not find suitable physical device!")
        os.exit(1)
    }

    backend.physicalDevice = best_device

    formats: []vk.SurfaceFormatKHR
    presentModes: []vk.PresentModeKHR
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(backend.physicalDevice, backend.surface, &backend.capabilities)

    formatCount: u32
    vk.GetPhysicalDeviceSurfaceFormatsKHR(backend.physicalDevice, backend.surface, &formatCount, nil)
    formats = make([]vk.SurfaceFormatKHR, formatCount)
    defer delete(formats)
    vk.GetPhysicalDeviceSurfaceFormatsKHR(backend.physicalDevice, backend.surface, &formatCount, raw_data(formats))
    
    modeCount: u32
    vk.GetPhysicalDeviceSurfacePresentModesKHR(backend.physicalDevice, backend.surface, &modeCount, nil)
    presentModes = make([]vk.PresentModeKHR, modeCount)
    defer delete(presentModes)
    vk.GetPhysicalDeviceSurfacePresentModesKHR(backend.physicalDevice, backend.surface, &modeCount, raw_data(presentModes))
    
    backend.surfaceFormat = formats[0]
    for format in formats {
        if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
            backend.surfaceFormat = format
            break
        }
    }
    
    backend.presentMode = .FIFO
    for mode in presentModes {
        if mode == .MAILBOX {
            backend.presentMode = mode
            break
        }
    }



    count = 0
    vk.GetPhysicalDeviceQueueFamilyProperties(backend.physicalDevice, &count, nil)
    queueFamilies := make([]vk.QueueFamilyProperties, count)
    defer delete(queueFamilies)
    vk.GetPhysicalDeviceQueueFamilyProperties(backend.physicalDevice, &count, raw_data(queueFamilies))

    chose_queue_family := false

    for family, i in queueFamilies {
        // fmt.printfln("%v", family)

        fmt.printf("Queue family %d:\n", i)
        fmt.printf("    Count: %d\n", family.queueCount)
        fmt.printf("    Graphics: %v\n", .GRAPHICS in family.queueFlags)
        fmt.printf("    Compute: %v\n", .COMPUTE in family.queueFlags)
        fmt.printf("    Transfer: %v\n", .TRANSFER in family.queueFlags)

        if .GRAPHICS in family.queueFlags {
            // @TODO Can multiple families have GRAPHICS? (mine does not, AMD Radeon 7900 XT)
            if !chose_queue_family {
                chose_queue_family = true
                backend.graphics_queueFamilyIndex = cast(u32)i
            }
        }
    }
    for family, i in queueFamilies {
        presentSupport: b32
        res = vk.GetPhysicalDeviceSurfaceSupportKHR(backend.physicalDevice, cast(u32)i, backend.surface, &presentSupport)
        check_error(res, "ERROR: GetPhysicalDeviceSurfaceSupportKHR")
        if presentSupport {
            backend.present_queueFamilyIndex = cast(u32)i
            break
        }
    }

    if backend.present_queueFamilyIndex != backend.graphics_queueFamilyIndex {
        // @TODO fix
        fmt.println("PRESENT and GRAPHICS QUEUE FAMILY are different, implement this!")
        os.exit(1)

        // Below is some useful code down the line

        // if graphics_queueFamilyIndex != present_queueFamilyIndex {
        //     swapchainCreateInfo.imageSharingMode = .CONCURRENT
        //     swapchainCreateInfo.queueFamilyIndexCount = 2
        //     swapchainCreateInfo.pQueueFamilyIndices = raw_data(queueFamilyIndices)
        // } else {
        //     swapchainCreateInfo.imageSharingMode = .EXCLUSIVE
        // }
    }

    prio: f32 = 1.0
    queueCreateInfo: vk.DeviceQueueCreateInfo = {
        sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
        queueFamilyIndex = backend.graphics_queueFamilyIndex,
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

    res = vk.CreateDevice(backend.physicalDevice, &createInfo, nil, &backend.device)
    check_error(res, "Could not create device")

    // @TODO Do we want to get more queues, not use index 0
    vk.GetDeviceQueue(backend.device, backend.graphics_queueFamilyIndex, 0, &backend.graphicsQueue)
}

create_pipeline :: proc (backend: ^VulkanBackend, vert_shader: vk.ShaderModule, frag_shader: vk.ShaderModule, vertexLayout: ^VertexLayout) {
    res: vk.Result

    vertexBindingDescription: vk.VertexInputBindingDescription
    vertexAttributeDescriptions: [8]vk.VertexInputAttributeDescription
    vertexAttributeDescriptions_count: u32


    vertexBindingDescription.binding = 0
    vertexBindingDescription.stride = cast(u32)vertexLayout.stride
    vertexBindingDescription.inputRate = .VERTEX

    for i in 0..<vertexLayout.attributeCount {
        attr := &vertexLayout.attributes[i]
        vertexAttributeDescriptions[vertexAttributeDescriptions_count].binding = 0
        vertexAttributeDescriptions[vertexAttributeDescriptions_count].location = cast(u32)attr.location
        vertexAttributeDescriptions[vertexAttributeDescriptions_count].offset = cast(u32)vertexLayout.attributesOffsets[i]
        switch attr.format {
            case .FLOAT32_1: vertexAttributeDescriptions[vertexAttributeDescriptions_count].format = .R32_SFLOAT
            case .FLOAT32_2: vertexAttributeDescriptions[vertexAttributeDescriptions_count].format = .R32G32_SFLOAT
            case .FLOAT32_3: vertexAttributeDescriptions[vertexAttributeDescriptions_count].format = .R32G32B32_SFLOAT
            case .FLOAT32_4: vertexAttributeDescriptions[vertexAttributeDescriptions_count].format = .R32G32B32A32_SFLOAT
            case .UINT32_1: vertexAttributeDescriptions[vertexAttributeDescriptions_count].format = .R32_UINT
            case .UINT32_2: vertexAttributeDescriptions[vertexAttributeDescriptions_count].format = .R32G32_UINT
            case .UINT32_3: vertexAttributeDescriptions[vertexAttributeDescriptions_count].format = .R32G32B32_UINT
            case .UINT32_4: vertexAttributeDescriptions[vertexAttributeDescriptions_count].format = .R32G32B32A32_UINT
        }
        vertexAttributeDescriptions_count += 1
    }

    vertPipelineStageInfo: vk.PipelineShaderStageCreateInfo = {
        sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage = { .VERTEX },
        module = vert_shader,
        pName = "main",
    }

    fragPipelineStageInfo: vk.PipelineShaderStageCreateInfo = {
        sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage = { .FRAGMENT },
        module = frag_shader,
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
        vertexBindingDescriptionCount = 1,
        pVertexBindingDescriptions = &vertexBindingDescription,
        vertexAttributeDescriptionCount = vertexAttributeDescriptions_count,
        pVertexAttributeDescriptions = &vertexAttributeDescriptions[0],
    }

    inputAssembly: vk.PipelineInputAssemblyStateCreateInfo = {
        sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology = .TRIANGLE_LIST,
        primitiveRestartEnable = false,
    }

    viewport: vk.Viewport = {
        x = 0.0,
        y = 0.0,
        width = cast(f32)backend.extent.width,
        height = cast(f32)backend.extent.height,
        minDepth = 0.0,
        maxDepth = 1.0,
    }

    scissor: vk.Rect2D = {
        offset = {0, 0},
        extent = backend.extent,
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

    push_constant_range: vk.PushConstantRange = {
        stageFlags = {.VERTEX, .FRAGMENT},
        offset     = 0,
        size       = size_of(Rect_Push_Constants),
    }

    pipelineLayoutInfo: vk.PipelineLayoutCreateInfo = {
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = 0,
        pSetLayouts = nil,
        pushConstantRangeCount = 1,
        pPushConstantRanges = &push_constant_range,
        // pushConstantRangeCount = 0,
        // pPushConstantRanges = nil,
    }

    res = vk.CreatePipelineLayout(backend.device, &pipelineLayoutInfo, nil, &backend.pipelineLayout)
    check_error(res, "failed to create pipeline layout!")
    
    colorAttachment: vk.AttachmentDescription = {
        format = backend.surfaceFormat.format,
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

    res = vk.CreateRenderPass(backend.device, &renderPassInfo, nil, &backend.renderPass)
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

        layout = backend.pipelineLayout,
        renderPass = backend.renderPass,
        subpass = 0,
        basePipelineHandle = 0,
        basePipelineIndex = -1,
    }
    
    res = vk.CreateGraphicsPipelines(backend.device, 0, 1, &pipelineInfo, nil, &backend.graphicsPipeline)
    check_error(res, "Failed creating graphics pipeline")

     
    poolInfo: vk.CommandPoolCreateInfo = {
        sType = .COMMAND_POOL_CREATE_INFO,
        flags = { .RESET_COMMAND_BUFFER },
        queueFamilyIndex = backend.graphics_queueFamilyIndex,
    }

    res = vk.CreateCommandPool(backend.device, &poolInfo, nil, &backend.commandPool)
    check_error(res, "failed to create command pool")

    allocInfo: vk.CommandBufferAllocateInfo = {
        sType = .COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool = backend.commandPool,
        level = .PRIMARY,
        commandBufferCount = MAX_FRAMES_IN_FLIGHT,
    }

    res = vk.AllocateCommandBuffers(backend.device, &allocInfo, &backend.commandBuffers[0])
    check_error(res, "failed to allocate command buffers!")

}

record_command_buffer :: proc (backend: ^VulkanBackend, commandBuffer: vk.CommandBuffer, imageIndex: u32, mesh: ^Mesh, push: ^Rect_Push_Constants) {
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
        renderPass = backend.renderPass,
        framebuffer = backend.swapchainFramebuffers[imageIndex],
        renderArea = {
            offset = {0, 0},
            extent = backend.extent,
        },
    }

    clearColor: vk.ClearValue = { color = { float32 = { 0.0, 0.0, 0.0, 1.0 }}};
    renderPassInfo.clearValueCount = 1;
    renderPassInfo.pClearValues = &clearColor;
    
    vk.CmdBeginRenderPass(commandBuffer, &renderPassInfo, .INLINE);
    check_error(res, "failed to begin render pass")

    vk.CmdBindPipeline(commandBuffer, .GRAPHICS, backend.graphicsPipeline);
    check_error(res, "failed to bind pipeline")



    vk_buffer := mesh.vertexBuffer.internal.(vulkan_VertexBuffer).buffer
    
    vertexBuffers: []vk.Buffer = {vk_buffer};
    offsets: []vk.DeviceSize = {0};
    vk.CmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], raw_data(offsets))
    check_error(res, "failed to bind vertex buffers")

    viewport: vk.Viewport = {
        x = 0.0,
        y = 0.0,
        width = cast(f32)(backend.extent.width),
        height = cast(f32)(backend.extent.height),
        minDepth = 0.0,
        maxDepth = 1.0,
    }
    vk.CmdSetViewport(commandBuffer, 0, 1, &viewport);

    scissor: vk.Rect2D = {
        offset = {0, 0},
        extent = backend.extent,
    }
    vk.CmdSetScissor(commandBuffer, 0, 1, &scissor);

    vk.CmdPushConstants(
        commandBuffer,
        backend.pipelineLayout,
        {.VERTEX, .FRAGMENT},
        0,
        size_of(Rect_Push_Constants),
        push,
    )
    vk.CmdDraw(commandBuffer, cast(u32)mesh.vertexBuffer.vertex_count, 1, 0, 0)
    // vk.CmdDraw(commandBuffer, 6, 1, 0, 0)

    vk.CmdEndRenderPass(commandBuffer)

    res = vk.EndCommandBuffer(commandBuffer)
    check_error(res, "failed to record command buffer")
}

    
recreate_swapchain :: proc (backend: ^VulkanBackend) {
    // @TODO Handle minimize window, https://vulkan-tutorial.com/Drawing_a_triangle/Swap_chain_recreation

    vk.DeviceWaitIdle(backend.device);

    // cleanup swapchain

    for framebuffer in backend.swapchainFramebuffers {
        vk.DestroyFramebuffer(backend.device, framebuffer, nil)
    }
    for image in backend.imageViews {
        vk.DestroyImageView(backend.device, image, nil)
    }
    vk.DestroySwapchainKHR(backend.device, backend.swapchain, nil)

    // make swapchain
    
    create_swapchain(backend)
}

create_swapchain :: proc (backend: ^VulkanBackend) {
    res: vk.Result
    backend.imageCount = backend.capabilities.minImageCount + 1
    if backend.capabilities.maxImageCount > 0 && backend.imageCount > backend.capabilities.maxImageCount {
        backend.imageCount = backend.capabilities.maxImageCount
    }

    backend.extent = backend.capabilities.currentExtent

    createInfo: vk.SwapchainCreateInfoKHR = {
        sType = .SWAPCHAIN_CREATE_INFO_KHR,
        surface = backend.surface,
        minImageCount = backend.imageCount,
        imageFormat = backend.surfaceFormat.format,
        imageColorSpace = backend.surfaceFormat.colorSpace,
        imageExtent = backend.extent,
        imageArrayLayers = 1,
        imageUsage = { .COLOR_ATTACHMENT },
    }
    
    if backend.present_queueFamilyIndex != backend.graphics_queueFamilyIndex {
        fmt.println("we assume graphics, present queue family index, this is not the case")
        os.exit(1)
    }
    createInfo.imageSharingMode = .EXCLUSIVE
    // set queueFamilyINdexCount and pQueueFamilyIndices otherwise

    createInfo.preTransform = backend.capabilities.currentTransform
    createInfo.compositeAlpha = { .OPAQUE }  // @TODO Is this where we can specify alpha and have transparent windows, like transparent background ofr code editors or game launcher with rounded edges?

    createInfo.presentMode = backend.presentMode
    createInfo.clipped = true
    createInfo.oldSwapchain = cast(vk.SwapchainKHR)0

    res = vk.CreateSwapchainKHR(backend.device, &createInfo, nil, &backend.swapchain)
    check_error(res, "could not make swapchain")


    vk.GetSwapchainImagesKHR(backend.device, backend.swapchain, &backend.imageCount, nil)
    backend.images = make([]vk.Image, backend.imageCount)
    vk.GetSwapchainImagesKHR(backend.device, backend.swapchain, &backend.imageCount, raw_data(backend.images))


    backend.imageViews = make([]vk.ImageView, len(backend.images))

    for &image, index in backend.imageViews {
        createInfo: vk.ImageViewCreateInfo = {
            sType = .IMAGE_VIEW_CREATE_INFO,
            image = backend.images[index],
            viewType = .D2,
            format = backend.surfaceFormat.format,
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

        res = vk.CreateImageView(backend.device, &createInfo, nil, &image)
        check_error(res, "Failed making image view")

    }

    backend.swapchainFramebuffers = make([]vk.Framebuffer, len(backend.imageViews))
    for view, i in backend.imageViews {
        attachments: []vk.ImageView = {
            view
        }
        framebufferInfo: vk.FramebufferCreateInfo = {
            sType = .FRAMEBUFFER_CREATE_INFO,
            renderPass = backend.renderPass,
            attachmentCount = 1,
            pAttachments = &attachments[0],
            width = backend.extent.width,
            height = backend.extent.height,
            layers = 1,
        }

        res = vk.CreateFramebuffer(backend.device, &framebufferInfo, nil, &backend.swapchainFramebuffers[i])
        check_error(res, "failed to create framebuffer!")
    }
}
