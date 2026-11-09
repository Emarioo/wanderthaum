package graphics

import "core:mem"
import "core:strings"
import "core:fmt"
import "base:intrinsics"

import vk "vendor:vulkan"

import "./shaderc"





vulkan_make_mesh :: proc (backend: ^VulkanBackend, vertices: []f32, indices: []u32, mesh: ^Mesh) -> bool {
    res: vk.Result

    {
        bufferInfo: vk.BufferCreateInfo = {
            sType = .BUFFER_CREATE_INFO,
            size = cast(vk.DeviceSize)(len(vertices) * size_of(vertices[0])),
            usage = {.VERTEX_BUFFER},
            sharingMode = .EXCLUSIVE,
        }

        buffer: vk.Buffer
        bufferMemory: vk.DeviceMemory

        res = vk.CreateBuffer(backend.device, &bufferInfo, nil, &buffer)
        check_error(res, "could not create vertex buffer")

        memRequirements: vk.MemoryRequirements
        vk.GetBufferMemoryRequirements(backend.device, buffer, &memRequirements)
        check_error(res, "could not get buffer memory requirements")

        memoryTypeIndex := findMemoryType(backend, memRequirements.memoryTypeBits, { .HOST_VISIBLE, .HOST_COHERENT })

        allocInfo: vk.MemoryAllocateInfo
        allocInfo.sType = .MEMORY_ALLOCATE_INFO
        allocInfo.allocationSize = memRequirements.size
        allocInfo.memoryTypeIndex = cast(u32)memoryTypeIndex


        res = vk.AllocateMemory(backend.device, &allocInfo, nil, &bufferMemory)
        check_error(res, "could not allocate vertex buffer memory")

        res = vk.BindBufferMemory(backend.device, buffer, bufferMemory, 0)
        check_error(res, "could not bind vertex buffer memory")

        mapped_data: rawptr
        res = vk.MapMemory(backend.device, bufferMemory, 0, bufferInfo.size, {}, &mapped_data)
        check_error(res, "could not map vertex buffer memory")

        intrinsics.mem_copy(mapped_data, raw_data(vertices), bufferInfo.size)
        
        vk.UnmapMemory(backend.device, bufferMemory)
        check_error(res, "could not unmap vertex buffer memory")

        tmp_vb: vulkan_VertexBuffer
        tmp_vb.buffer = buffer
        tmp_vb.bufferMemory = bufferMemory

        mesh.vertexBuffer.internal = tmp_vb
    }
    
    if len(indices) > 0 {
        bufferInfo: vk.BufferCreateInfo = {
            sType = .BUFFER_CREATE_INFO,
            size = cast(vk.DeviceSize)(len(indices) * size_of(indices[0])),
            usage = {.INDEX_BUFFER},
            sharingMode = .EXCLUSIVE,
        }

        buffer: vk.Buffer
        bufferMemory: vk.DeviceMemory

        res = vk.CreateBuffer(backend.device, &bufferInfo, nil, &buffer)
        check_error(res, "could not create vertex buffer")

        memRequirements: vk.MemoryRequirements
        vk.GetBufferMemoryRequirements(backend.device, buffer, &memRequirements)
        check_error(res, "could not get buffer memory requirements")

        memoryTypeIndex := findMemoryType(backend, memRequirements.memoryTypeBits, { .HOST_VISIBLE, .HOST_COHERENT })

        allocInfo: vk.MemoryAllocateInfo
        allocInfo.sType = .MEMORY_ALLOCATE_INFO
        allocInfo.allocationSize = memRequirements.size
        allocInfo.memoryTypeIndex = cast(u32)memoryTypeIndex


        res = vk.AllocateMemory(backend.device, &allocInfo, nil, &bufferMemory)
        check_error(res, "could not allocate vertex buffer memory")

        res = vk.BindBufferMemory(backend.device, buffer, bufferMemory, 0)
        check_error(res, "could not bind vertex buffer memory")

        mapped_data: rawptr
        res = vk.MapMemory(backend.device, bufferMemory, 0, bufferInfo.size, {}, &mapped_data)
        check_error(res, "could not map vertex buffer memory")

        intrinsics.mem_copy(mapped_data, raw_data(indices), bufferInfo.size)
        
        vk.UnmapMemory(backend.device, bufferMemory)
        check_error(res, "could not unmap vertex buffer memory")

        tmp_ib: vulkan_IndexBuffer
        tmp_ib.buffer = buffer
        tmp_ib.bufferMemory = bufferMemory
        mesh.indexBuffer.internal = tmp_ib
    }

    return true
}

findMemoryType :: proc (backend: ^VulkanBackend, typeFilter: u32, properties: vk.MemoryPropertyFlags) -> i32 {
    memProperties: vk.PhysicalDeviceMemoryProperties
    vk.GetPhysicalDeviceMemoryProperties(backend.physicalDevice, &memProperties);

    for i in 0..<memProperties.memoryTypeCount {
        flags: vk.MemoryPropertyFlags = memProperties.memoryTypes[i].propertyFlags
        if (typeFilter & (1 << i)) != 0 && (flags >= properties) {
            return cast(i32)i
        }
    }

    check_error(vk.Result.ERROR_UNKNOWN, "could not find suitable memory type")
    return -1
}

convert_glsl_to_spirv :: proc (backend: ^VulkanBackend, source: string, kind: shaderc.shaderKind, path: string) -> []u8 {
    if backend.compiler == nil {
        return nil
    }

    options := shaderc.compile_options_initialize()
    if options == nil {
        fmt.println("Failed to initialize shaderc options")
        return nil
    }
    defer shaderc.compile_options_release(options)

    shaderc.compile_options_set_source_language(options, .Glsl)

    // @TODO Don't hardcode vulkan version
    //   We have other places where we setup the vulkan version.
    shaderc.compile_options_set_target_env(options, shaderc.targetEnv.Vulkan, cast(u32)shaderc.envVersion.Vulkan1_4)
    shaderc.compile_options_set_target_spirv(options, shaderc.spirvVersion.Spv1_6)

    result := shaderc.compile_into_spv(
        backend.compiler,
        strings.unsafe_string_to_cstring(source), // See note below
        len(source),
        kind,
        strings.unsafe_string_to_cstring(path),
        "main",
        options,
    )
    if result == nil {
        fmt.println("shaderc returned a null result")
        return nil
    }
    defer shaderc.result_release(result)

    if shaderc.result_get_compilation_status(result) != .Success {
        fmt.println(shaderc.result_get_error_message(result))
        return nil
    }

    byte_count := int(shaderc.result_get_length(result))
    if byte_count == 0 {
        fmt.println("Shader compilation produced empty SPIR-V")
        return nil
    }

    bytes := make([]u8, byte_count)
    mem.copy(
        raw_data(bytes),
        shaderc.result_get_bytes(result),
        byte_count,
    )

    return bytes
}


vulkan_make_shader_from_glsl :: proc (backend: ^VulkanBackend, vertex_text, fragment_text: string, shader: ^vulkan_Shader, path: string) -> bool {
    res: vk.Result
    {
        vert_data := convert_glsl_to_spirv(backend, vertex_text, .VertexShader, path)
        if vert_data == nil {
            return false
        }
        defer delete(vert_data)

        // if !strings.contains(path, "ui") {
        //     return false
        // }

        createInfo: vk.ShaderModuleCreateInfo = {
            sType = .SHADER_MODULE_CREATE_INFO,
            codeSize = len(vert_data),
            pCode = cast(^u32)raw_data(vert_data),
        }
        
        res = vk.CreateShaderModule(backend.device, &createInfo, nil, &shader.vert_shader)
        check_error(res, "Failed creating vert shader module")
    }
    {
        frag_data := convert_glsl_to_spirv(backend, fragment_text, .FragmentShader, path)
        if frag_data == nil {
            // @TODO Leaking shader module above if we fail here
            return false
        }
        defer delete(frag_data)
        createInfo: vk.ShaderModuleCreateInfo
        createInfo.sType = .SHADER_MODULE_CREATE_INFO
        createInfo.codeSize = len(frag_data)
        createInfo.pCode = cast(^u32)raw_data(frag_data)

        res = vk.CreateShaderModule(backend.device, &createInfo, nil, &shader.frag_shader)
        check_error(res, "Failed creating frag shader module")
    }

    return true
}
