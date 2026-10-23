-- Original photos are decoded on Kindle with the installed KOReader libraries.
-- Only this worker writes generated frames; album.sh owns playlist activation.
require("ffi/loadlib")
local ffi = require("ffi")
local BB = require("ffi/blitbuffer")
local Jpeg = require("ffi/jpeg")
local Png = require("ffi/png")
local lfs = require("libs/libkoreader-lfs")
local crypto = ffi.loadlib("crypto", "57")
ffi.cdef[[unsigned char *SHA256(const unsigned char *, size_t, unsigned char *);]]
local lodepng = ffi.loadlib("lodepng")
local M = {}
local W, H = 1264, 1680
local marker = "kindle-oasis-album-20261022\n"
local layouts, variants = {"crop", "contain"}, {"clean", "10", "30", "60", "300"}

local function read(path, limit)
    local f = assert(io.open(path, "rb"), "read_failed")
    local data = f:read(limit or "*a")
    f:close()
    return data or ""
end

local function write(path, data)
    local f = assert(io.open(path, "wb"), "write_failed")
    local ok = f:write(data)
    local closed = f:close()
    assert(ok and closed, "write_failed")
end

local function atomic(path, data)
    write(path .. ".tmp", data)
    assert(os.rename(path .. ".tmp", path), "rename_failed")
end

function M.sha256(data)
    local out = ffi.new("unsigned char[32]")
    assert(crypto.SHA256(data, #data, out) ~= nil, "hash_failed")
    return (ffi.string(out, 32):gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local function be16(s, at) return s:byte(at) * 256 + s:byte(at + 1) end
local function be32(s, at) return be16(s, at) * 65536 + be16(s, at + 2) end

local function exif_orientation(exif)
    if exif:sub(1, 6) ~= "Exif\0\0" then return 1 end
    local t = exif:sub(7)
    local little = t:sub(1, 2) == "II"
    if not little and t:sub(1, 2) ~= "MM" then return 1 end
    local function number(at, n)
        if at < 1 or at + n - 1 > #t then return nil end
        local v = 0
        for i = 0, n - 1 do
            local p = little and at + n - i - 1 or at + i
            v = v * 256 + t:byte(p)
        end
        return v
    end
    if number(3, 2) ~= 42 then return 1 end
    local offset = number(5, 4)
    if not offset then return 1 end
    local count = number(offset + 1, 2)
    if not count or count > 4096 then return 1 end
    for i = 0, count - 1 do
        local at = offset + 3 + i * 12
        if number(at, 2) == 274 and number(at + 2, 2) == 3 and number(at + 4, 4) == 1 then
            local value = number(at + 8, 2)
            if value and value >= 1 and value <= 8 then return value end
        end
    end
    return 1
end

function M.inspect(data, extension)
    local w, h, orientation = nil, nil, 1
    if extension == "png" then
        assert(#data >= 33 and data:sub(1, 8) == "\137PNG\r\n\26\n"
            and data:sub(13, 16) == "IHDR", "invalid_png")
        w, h = be32(data, 17), be32(data, 21)
    else
        assert(data:sub(1, 2) == "\255\216", "invalid_jpeg")
        local at, segments = 3, 0
        while at + 3 <= #data and segments < 4096 do
            assert(data:byte(at) == 255, "invalid_jpeg")
            while data:byte(at) == 255 do at = at + 1 end
            local kind = data:byte(at)
            at = at + 1
            if kind == 217 or kind == 218 then break end
            if kind ~= 1 and (kind < 208 or kind > 215) then
                assert(at + 1 <= #data, "invalid_jpeg")
                local length = be16(data, at)
                assert(length >= 2 and at + length - 1 <= #data, "invalid_jpeg")
                if kind == 225 then orientation = exif_orientation(data:sub(at + 2, at + length - 1)) end
                if kind >= 192 and kind <= 207 and kind ~= 196 and kind ~= 200 and kind ~= 204 then
                    assert(length >= 8, "invalid_jpeg")
                    h, w = be16(data, at + 3), be16(data, at + 5)
                end
                at = at + length
            end
            segments = segments + 1
        end
    end
    assert(w and h and w > 0 and h > 0 and w <= 20000 and h <= 20000, "invalid_dimensions")
    assert(w * h <= (extension == "png" and 20000000 or 80000000), "image_too_large")
    return w, h, orientation
end

local function decode(path, data, extension, width, height)
    if extension ~= "png" then
        local image = Jpeg.openDocumentFromMem(data, false)
        assert(image:getWidth() == width and image:getHeight() == height, "dimensions_changed")
        return image
    end
    local ok, decoded = Png.decodeFromFile(path, 4)
    assert(ok, "decode_failed")
    local rgba = BB.new(decoded.width, decoded.height, BB.TYPE_BBRGB32, decoded.data)
    rgba:setAllocated(1)
    assert(decoded.width == width and decoded.height == height, "dimensions_changed")
    local gray = BB.new(width, height, BB.TYPE_BB8)
    gray:paintRect(0, 0, width, height, BB.COLOR_WHITE)
    gray:alphablitFrom(rgba)
    rgba:free()
    return gray
end

-- Fit directly into a screen-sized buffer. Rotation/mirroring is part of the
-- sampling transform, avoiding a second full-resolution copy of a camera JPG.
function M.fit(image, orientation, layout)
    local sw, sh = image:getWidth(), image:getHeight()
    local ow, oh = sw, sh
    if orientation >= 5 then ow, oh = sh, sw end
    local scale = (layout == "crop" and math.max or math.min)(W / ow, H / oh)
    local dw, dh = W, H
    if layout == "contain" then
        dw, dh = math.min(W, math.floor(ow * scale + 0.5)), math.min(H, math.floor(oh * scale + 0.5))
    end
    local left, top = math.floor((W - dw) / 2), math.floor((H - dh) / 2)
    local canvas = BB.new(W, H, BB.TYPE_BB8)
    canvas:paintRect(0, 0, W, H, BB.COLOR_WHITE)
    local src = ffi.cast("const unsigned char *", image.data)
    local dst = ffi.cast("unsigned char *", canvas.data)
    local stride = image.stride
    for y = top, top + dh - 1 do
        local oy = (y + 0.5 - H / 2) / scale + (oh - 1) / 2
        for x = left, left + dw - 1 do
            local ox = (x + 0.5 - W / 2) / scale + (ow - 1) / 2
            local sx, sy = ox, oy
            if orientation == 2 then sx = sw - 1 - ox
            elseif orientation == 3 then sx, sy = sw - 1 - ox, sh - 1 - oy
            elseif orientation == 4 then sy = sh - 1 - oy
            elseif orientation == 5 then sx, sy = oy, ox
            elseif orientation == 6 then sx, sy = oy, sh - 1 - ox
            elseif orientation == 7 then sx, sy = sw - 1 - oy, sh - 1 - ox
            elseif orientation == 8 then sx, sy = sw - 1 - oy, ox end
            sx, sy = math.max(0, math.min(sw - 1, sx)), math.max(0, math.min(sh - 1, sy))
            local x0, y0 = math.floor(sx), math.floor(sy)
            local x1, y1 = math.min(sw - 1, x0 + 1), math.min(sh - 1, y0 + 1)
            local fx, fy = sx - x0, sy - y0
            local a = src[y0 * stride + x0] * (1 - fx) + src[y0 * stride + x1] * fx
            local b = src[y1 * stride + x0] * (1 - fx) + src[y1 * stride + x1] * fx
            dst[y * canvas.stride + x] = math.floor(a * (1 - fy) + b * fy + 0.5)
        end
    end
    return canvas
end

local function encode(path, image)
    local state = ffi.new("LodePNGState[1]")
    local output, size = ffi.new("unsigned char*[1]"), ffi.new("size_t[1]")
    lodepng.lodepng_state_init(state)
    state[0].info_raw.colortype, state[0].info_png.color.colortype = 0, 0
    state[0].info_raw.bitdepth, state[0].info_png.color.bitdepth = 8, 8
    state[0].encoder.auto_convert = 0
    local err = lodepng.lodepng_encode(output, size, ffi.cast("const unsigned char *", image.data), W, H, state)
    lodepng.lodepng_state_cleanup(state)
    assert(err == 0, "encode_failed")
    local data = ffi.string(output[0], size[0])
    ffi.C.free(output[0])
    write(path, data)
end

local function png_valid(path, size)
    local attr = lfs.symlinkattributes(path)
    if not attr or attr.mode ~= "file" or attr.size ~= size or size < 33 then return false end
    local header = read(path, 26)
    return #header == 26 and header:sub(1, 8) == "\137PNG\r\n\26\n"
        and be32(header, 17) == W and be32(header, 21) == H
        and header:byte(25) == 8 and header:byte(26) == 0
end

local function cached(base, prefix)
    local f = io.open(base .. "/assets/" .. prefix .. ".complete", "rb")
    if not f then return false end
    local count = 0
    for line in f:lines() do
        local size, suffix = line:match("^(%d+) ([a-z]+%-%w+%.png)$")
        if not size or not png_valid(base .. "/assets/" .. prefix .. "-" .. suffix, tonumber(size)) then
            f:close(); return false
        end
        count = count + 1
    end
    f:close()
    return count == 10
end

local function prepare(base, app, stage, path, data, extension, prefix)
    local w, h, orientation = M.inspect(data, extension)
    local image = decode(path, data, extension, w, h)
    local records = {}
    for _, layout in ipairs(layouts) do
        local clean = M.fit(image, orientation, layout)
        for _, variant in ipairs(variants) do
            local frame = clean
            if variant ~= "clean" then
                local ok, bar = Png.decodeFromFile(app .. "/import-ui/" .. layout .. "-" .. variant .. ".png", 1)
                assert(ok and bar.width == W and bar.height == 200 and bar.ncomp == 1, "invalid_controls")
                local overlay = BB.new(W, 200, BB.TYPE_BB8, bar.data)
                overlay:setAllocated(1)
                frame = clean:copy()
                frame:blitFrom(overlay, 0, 1480)
                overlay:free()
            end
            local suffix = layout .. "-" .. variant .. ".png"
            local target = stage .. "/" .. suffix
            encode(target, frame)
            if frame ~= clean then frame:free() end
            local size = assert(lfs.attributes(target, "size"), "write_failed")
            assert(png_valid(target, size), "invalid_output")
            records[#records + 1] = tostring(size) .. " " .. suffix .. "\n"
        end
        clean:free()
    end
    image:free()
    for _, layout in ipairs(layouts) do
        for _, variant in ipairs(variants) do
            local suffix = layout .. "-" .. variant .. ".png"
            assert(os.rename(stage .. "/" .. suffix, base .. "/assets/" .. prefix .. "-" .. suffix), "publish_failed")
        end
    end
    atomic(base .. "/assets/" .. prefix .. ".complete", table.concat(records))
end

local function demo_only(base, app, original)
    local f = io.open(app .. "/import-ui/demo.sha256", "rb")
    if not f then return false end
    local checks = f:read("*a"); f:close()
    local count = 0
    for hash, path in checks:gmatch("([a-f0-9]+) ([^\n]+)\n") do
        if #hash ~= 64 or (path ~= "slides.txt" and not path:match("^assets/photo%-%d%d%d%-%a+%-%w+%.png$")) then return false end
        local ok, data = pcall(read, base .. "/" .. path)
        if not ok or M.sha256(data) ~= hash then return false end
        count = count + 1
    end
    return count == 31 and original == "photo-001\nphoto-002\nphoto-003\n"
end

function M.run(photos, base, app, runtime)
    assert(read(base .. "/project-id") == marker, "wrong_device")
    assert(read(runtime .. "/project-id") == marker, "wrong_session")
    local original = read(base .. "/slides.txt")
    local playlist, seen = {}, {}
    for prefix in original:gmatch("([^\n]+)\n") do
        assert(prefix:match("^[A-Za-z0-9_-]+$"), "invalid_playlist")
        playlist[#playlist + 1], seen[prefix] = prefix, true
    end
    assert(#playlist >= 1 and #playlist <= 500, "invalid_playlist")
    local files = {}
    for name in lfs.dir(photos) do
        local ext = name:match("%.([^.]+)$")
        ext = ext and ext:lower()
        if name:sub(1, 1) ~= "." and (ext == "jpg" or ext == "jpeg" or ext == "png") then
            local attr = lfs.symlinkattributes(photos .. "/" .. name)
            if attr and attr.mode == "file" then
                files[#files + 1] = {name = name, extension = ext, size = attr.size}
            end
        end
    end
    table.sort(files, function(a, b) return a.name:lower() < b.name:lower() end)
    local stage = base .. "/.photo-import"
    if lfs.attributes(stage) then
        assert(read(stage .. "/project-id") == marker, "foreign_stage")
    else
        assert(lfs.mkdir(stage), "mkdir_failed")
        write(stage .. "/project-id", marker)
    end
    local replace_demo = #files > 0 and demo_only(base, app, original)
    local added, failed, duplicate = 0, 0, 0
    atomic(runtime .. "/import-original", original)
    for i, file in ipairs(files) do
        if i > 500 then failed = failed + 1
        else
            local ok = pcall(function()
                assert(file.size > 0 and file.size <= 67108864, "file_too_large")
                assert(read(base .. "/project-id") == marker, "media_unavailable")
                local path = photos .. "/" .. file.name
                local data = read(path, 67108865)
                assert(#data == file.size, "source_changed")
                local prefix = "img-" .. M.sha256(data)
                if seen[prefix] then duplicate = duplicate + 1; return end
                assert((replace_demo and added == 0) or #playlist < 500, "album_full")
                if not cached(base, prefix) then prepare(base, app, stage, path, data, file.extension, prefix) end
                if replace_demo and added == 0 then playlist, seen = {}, {} end
                playlist[#playlist + 1], seen[prefix] = prefix, true
                added = added + 1
            end)
            if not ok then failed = failed + 1 end
        end
        collectgarbage("collect")
        atomic(runtime .. "/import-progress", string.format("%d %d %d %d\n", i, #files, failed, added))
    end
    if added > 0 then atomic(runtime .. "/import-pending", table.concat(playlist, "\n") .. "\n") end
    atomic(runtime .. "/import-result", string.format("%d %d %d %d\n", added, failed, duplicate, #playlist))
    atomic(runtime .. "/import-ready", "ready\n")
    return {added = added, failed = failed, duplicate = duplicate, count = #playlist}
end

if arg and arg[1] then
    local ok = pcall(M.run, arg[1], arg[2], arg[3], arg[4])
    if not ok then io.stderr:write("photo_import_worker_failed\n"); os.exit(1) end
end
return M
