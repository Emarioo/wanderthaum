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
    pick_device(backend)
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



// make_vertex_buffer :: proc (backend: ^VulkanBackend) {
//     res: vk.Result
//     backend.vertexBindingDescription.binding = 0
//     backend.vertexBindingDescription.stride = 5*4
//     backend.vertexBindingDescription.inputRate = .VERTEX

//     backend.vertexAttributeDescriptions[0].binding = 0
//     backend.vertexAttributeDescriptions[0].location = 0
//     backend.vertexAttributeDescriptions[0].format = .R32G32_SFLOAT
//     backend.vertexAttributeDescriptions[0].offset = 0
//     backend.vertexAttributeDescriptions[1].binding = 0
//     backend.vertexAttributeDescriptions[1].location = 1
//     backend.vertexAttributeDescriptions[1].format = .R32G32B32_SFLOAT
//     backend.vertexAttributeDescriptions[1].offset = 8

//     bufferInfo: vk.BufferCreateInfo = {
//         sType = .BUFFER_CREATE_INFO,
//         size = cast(vk.DeviceSize)(len(state.vertex_data) * 4),
//         usage = {.VERTEX_BUFFER},
//         sharingMode = .EXCLUSIVE,
//     }

//     res = vk.CreateBuffer(state.device, &bufferInfo, nil, &state.vertexBuffer)
//     check_error(res, "could not create vertex buffer")

//     memRequirements: vk.MemoryRequirements
//     vk.GetBufferMemoryRequirements(state.device, state.vertexBuffer, &memRequirements)
//     check_error(res, "could not get buffer memory requirements")

//     memoryTypeIndex := findMemoryType(state, memRequirements.memoryTypeBits, { .HOST_VISIBLE, .HOST_COHERENT })

//     allocInfo: vk.MemoryAllocateInfo
//     allocInfo.sType = .MEMORY_ALLOCATE_INFO
//     allocInfo.allocationSize = memRequirements.size
//     allocInfo.memoryTypeIndex = cast(u32)memoryTypeIndex


//     res = vk.AllocateMemory(state.device, &allocInfo, nil, &state.vertexBufferMemory)
//     check_error(res, "could not allocate vertex buffer memory")

//     res = vk.BindBufferMemory(state.device, state.vertexBuffer, state.vertexBufferMemory, 0)
//     check_error(res, "could not bind vertex buffer memory")

//     data: rawptr
//     res = vk.MapMemory(state.device, state.vertexBufferMemory, 0, bufferInfo.size, {}, &data)
//     check_error(res, "could not map vertex buffer memory")

//     intrinsics.mem_copy(data, raw_data(state.vertex_data), len(state.vertex_data) * 4)
    
//     vk.UnmapMemory(state.device, state.vertexBufferMemory)
//     check_error(res, "could not unmap vertex buffer memory")

// }


