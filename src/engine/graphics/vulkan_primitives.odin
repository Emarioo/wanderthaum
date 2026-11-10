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

        // @TODO We are leaking GPU buffers and memory here.
        //   We need to queue previous buffers for destruction.
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


vulkan_make_texture :: proc (backend: ^VulkanBackend, texture: ^Texture) {
    res: vk.Result
    
    tmp_texture, has_texture := texture.internal.(vulkan_Texture)
    if !has_texture {
        tmp_texture = {}
    } else if tmp_texture.image != 0 {
        vk.DestroyImageView(backend.device, tmp_texture.imageView, nil);
        vk.DestroyImage(backend.device, tmp_texture.image, nil);
        vk.FreeMemory(backend.device, tmp_texture.memory, nil);
        tmp_texture.image = 0
        tmp_texture.imageView = 0
        tmp_texture.memory = 0
    }
    

    // @TODO Optimize this code

    imageSize := texture.width * texture.height * 4
    stagingBuffer: vk.Buffer
    stagingBufferMemory: vk.DeviceMemory

    {
        
        bufferInfo: vk.BufferCreateInfo = {
            sType = .BUFFER_CREATE_INFO,
            size = cast(vk.DeviceSize)imageSize,
            usage = {.TRANSFER_SRC},
            sharingMode = .EXCLUSIVE,
        }

        res = vk.CreateBuffer(backend.device, &bufferInfo, nil, &stagingBuffer)
        check_error(res, "could not create vertex buffer")

        memRequirements: vk.MemoryRequirements
        vk.GetBufferMemoryRequirements(backend.device, stagingBuffer, &memRequirements)
        check_error(res, "could not get buffer memory requirements")

        memoryTypeIndex := findMemoryType(backend, memRequirements.memoryTypeBits, { .HOST_VISIBLE, .HOST_COHERENT })

        allocInfo: vk.MemoryAllocateInfo
        allocInfo.sType = .MEMORY_ALLOCATE_INFO
        allocInfo.allocationSize = memRequirements.size
        allocInfo.memoryTypeIndex = cast(u32)memoryTypeIndex


        res = vk.AllocateMemory(backend.device, &allocInfo, nil, &stagingBufferMemory)
        check_error(res, "could not allocate vertex buffer memory")

        res = vk.BindBufferMemory(backend.device, stagingBuffer, stagingBufferMemory, 0)
        check_error(res, "could not bind vertex buffer memory")

        mapped_data: rawptr
        res = vk.MapMemory(backend.device, stagingBufferMemory, 0, bufferInfo.size, {}, &mapped_data)
        check_error(res, "could not map vertex buffer memory")

        intrinsics.mem_copy(mapped_data, texture.raw_data, cast(int)imageSize)
        
        vk.UnmapMemory(backend.device, stagingBufferMemory)
        check_error(res, "could not unmap vertex buffer memory")
    }

    textureImage: vk.Image
    textureMemory: vk.DeviceMemory
    textureImageView: vk.ImageView

    imageInfo: vk.ImageCreateInfo = {
        sType = .IMAGE_CREATE_INFO,
        imageType = .D2,
        format = .R8G8B8A8_SRGB,
        extent = {cast(u32)texture.width, cast(u32)texture.height, 1},
        mipLevels = 1,
        arrayLayers = 1,
        samples = {._1},
        tiling = .OPTIMAL,
        usage = {.SAMPLED, .TRANSFER_DST},
        sharingMode = .EXCLUSIVE,
        initialLayout = .UNDEFINED,
    }

    res = vk.CreateImage(backend.device, &imageInfo, nil, &textureImage)
    check_error(res, "Failed creating texture image")


    requirements: vk.MemoryRequirements
    vk.GetImageMemoryRequirements(backend.device, textureImage, &requirements)

    allocationInfo: vk.MemoryAllocateInfo = {
        sType = .MEMORY_ALLOCATE_INFO,
        allocationSize = requirements.size,
        memoryTypeIndex = cast(u32)findMemoryType(
            backend,
            requirements.memoryTypeBits,
            {.DEVICE_LOCAL},
        ),
    }

    res = vk.AllocateMemory(backend.device, &allocationInfo, nil, &textureMemory)
    check_error(res, "Failed allocating texture image memory")

    res = vk.BindImageMemory(backend.device, textureImage, textureMemory, 0)
    check_error(res, "Failed binding texture image memory")


    transitionImageLayout(backend, textureImage, .R8G8B8A8_SRGB, .UNDEFINED, .TRANSFER_DST_OPTIMAL)

    copyBufferToImage(backend, stagingBuffer, textureImage, texture.width, texture.height)
    
    transitionImageLayout(backend, textureImage, .R8G8B8A8_SRGB, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL);

    vk.DestroyBuffer(backend.device, stagingBuffer, nil);
    vk.FreeMemory(backend.device, stagingBufferMemory, nil);


    viewInfo: vk.ImageViewCreateInfo = {
        sType = .IMAGE_VIEW_CREATE_INFO,
        image = textureImage,
        viewType = .D2,
        format = .R8G8B8A8_SRGB,
        subresourceRange = {
            aspectMask = {.COLOR},
            baseMipLevel = 0,
            levelCount = 1,
            baseArrayLayer = 0,
            layerCount = 1,
        },
    }

    res = vk.CreateImageView(backend.device, &viewInfo, nil, &textureImageView)
    check_error(res, "Failed creating image view")

    descriptorSets: [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet

    layouts: [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSetLayout
    for i in 0..<len(layouts) {
        layouts[i] = backend.descriptorSetLayout
    }

    allocInfo: vk.DescriptorSetAllocateInfo = {
        sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool = backend.descriptorPool,
        descriptorSetCount = cast(u32)MAX_FRAMES_IN_FLIGHT,
        pSetLayouts = &layouts[0],
    }
    res = vk.AllocateDescriptorSets(backend.device, &allocInfo, &descriptorSets[0])
    check_error(res, "failed to create descriptor sets")

    descriptorImageInfo: vk.DescriptorImageInfo = {
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
        imageView = textureImageView,
        sampler = backend.texture_sampler,
    }
    descriptorWrites: [MAX_FRAMES_IN_FLIGHT]vk.WriteDescriptorSet
    for i in 0..<len(descriptorWrites) {
        descriptorWrites[i] = {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = descriptorSets[i],
            dstBinding = 0,
            dstArrayElement = 0,
            descriptorType = .COMBINED_IMAGE_SAMPLER,
            descriptorCount = 1,
            pImageInfo = &descriptorImageInfo,
        }
    }

    vk.UpdateDescriptorSets(backend.device, MAX_FRAMES_IN_FLIGHT, &descriptorWrites[0], 0, nil);

    tmp_texture.image = textureImage
    tmp_texture.imageView = textureImageView
    tmp_texture.memory = textureMemory
    tmp_texture.descriptorSets = descriptorSets
    texture.internal = tmp_texture

}

copyBufferToImage :: proc (backend: ^VulkanBackend, buffer: vk.Buffer, image: vk.Image, width: u32, height: u32) {
    res: vk.Result

    commandBuffer := beginSingleTimeCommands(backend);

    region: vk.BufferImageCopy = {
        bufferOffset = 0,
        bufferRowLength = 0,
        bufferImageHeight = 0,

        imageSubresource = {
            aspectMask = { .COLOR },
            mipLevel = 0,
            baseArrayLayer = 0,
            layerCount = 1,
        },

        imageOffset = {0, 0, 0},
        imageExtent = {
            width,
            height,
            1
        },
    }

    vk.CmdCopyBufferToImage(
        commandBuffer,
        buffer,
        image,
        .TRANSFER_DST_OPTIMAL,
        1,
        &region
    );
    check_error(res, "Failed copybuffe to image")

    endSingleTimeCommands(backend, commandBuffer);
}

transitionImageLayout :: proc (backend: ^VulkanBackend, image: vk.Image, format: vk.Format, oldLayout: vk.ImageLayout, newLayout: vk.ImageLayout) {
    res: vk.Result

    commandBuffer := beginSingleTimeCommands(backend);

    barrier: vk.ImageMemoryBarrier = {
        sType = .IMAGE_MEMORY_BARRIER,
        oldLayout = oldLayout,
        newLayout = newLayout,
        srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        image = image,
        subresourceRange = {
            aspectMask = {.COLOR},
            baseMipLevel = 0,
            levelCount = 1,
            baseArrayLayer = 0,
            layerCount = 1,
        },
        srcAccessMask = { },
        dstAccessMask = { },
    }

    sourceStage: vk.PipelineStageFlags;
    destinationStage: vk.PipelineStageFlags;

    if (oldLayout == .UNDEFINED && newLayout == .TRANSFER_DST_OPTIMAL) {
        barrier.srcAccessMask = { }
        barrier.dstAccessMask = { .TRANSFER_WRITE }

        sourceStage = { .TOP_OF_PIPE }
        destinationStage = { .TRANSFER }
    } else if (oldLayout == .TRANSFER_DST_OPTIMAL && newLayout == .SHADER_READ_ONLY_OPTIMAL) {
        barrier.srcAccessMask = { .TRANSFER_WRITE }
        barrier.dstAccessMask = { .SHADER_READ }

        sourceStage = { .TRANSFER }
        destinationStage = { .FRAGMENT_SHADER }
    } else {
        panic("Unhandled image layout transition")
    }

    vk.CmdPipelineBarrier(
        commandBuffer,
        sourceStage, destinationStage,
        {},
        0, nil,
        0, nil,
        1, &barrier
    );

    endSingleTimeCommands(backend, commandBuffer);
}

beginSingleTimeCommands :: proc (backend: ^VulkanBackend) -> vk.CommandBuffer {
    res: vk.Result

    allocInfo: vk.CommandBufferAllocateInfo = {
        sType = .COMMAND_BUFFER_ALLOCATE_INFO,
        level = .PRIMARY,
        commandPool = backend.commandPool,
        commandBufferCount = 1,
    }

    commandBuffer: vk.CommandBuffer;
    res = vk.AllocateCommandBuffers(backend.device, &allocInfo, &commandBuffer);
    check_error(res, "Failed allocate command buffers, beign sinle time comands")


    beginInfo: vk.CommandBufferBeginInfo = {
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = { .ONE_TIME_SUBMIT },
    }

    res = vk.BeginCommandBuffer(commandBuffer, &beginInfo);
    check_error(res, "Failed being commaand buffer")

    return commandBuffer;
}
endSingleTimeCommands :: proc (backend: ^VulkanBackend, commandBuffer: vk.CommandBuffer) {
    res: vk.Result
    res = vk.EndCommandBuffer(commandBuffer);
    check_error(res, "Failed end command buffer ,end signle time comands")

    buffers: [1]vk.CommandBuffer = {
        commandBuffer
    }

    submitInfo: vk.SubmitInfo = {
        sType = .SUBMIT_INFO,
        commandBufferCount = 1,
        pCommandBuffers = &buffers[0],
    }

    res = vk.QueueSubmit(backend.graphicsQueue, 1, &submitInfo, 0);
    check_error(res, "Failed queuesubmit in end single time comomands")
    res = vk.QueueWaitIdle(backend.graphicsQueue);
    check_error(res, "Failed queuewaitIdle in end single time comomands")

    vk.FreeCommandBuffers(backend.device, backend.commandPool, 1, &buffers[0]);
}


