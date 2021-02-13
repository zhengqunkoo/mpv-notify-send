local utils = require "mp.utils"
local msg = require 'mp.msg'
local https = require "ssl.https"
local lunajson = require "lunajson"
local socket = require "socket"

local cover_filenames = { "cover.png", "cover.jpg", "cover.jpeg",
                          "folder.jpg", "folder.png", "folder.jpeg",
                          "AlbumArtwork.png", "AlbumArtwork.jpg", "AlbumArtwork.jpeg" }

function notify(summary, body, options)
    local option_args = {}
    for key, value in pairs(options or {}) do
        table.insert(option_args, string.format("--%s=%s", key, value))
    end
    return mp.command_native({
        "run", "notify-send", unpack(option_args),
        summary, body,
    })
end

function notify_media(title, origin, thumbnail)
    return notify(title, origin, {
        -- For some inscrutable reason, GNOME 3.24.2
        -- nondeterministically fails to pick up the notification icon
        -- if either of these two parameters are present.
        --
        -- urgency = "low",
        -- ["app-name"] = "mpv",

        -- ...and this one makes notifications nondeterministically
        -- fail to appear altogether.
        --
        -- hint = "string:desktop-entry:mpv",

        icon = thumbnail or "mpv",
    })
end

function file_exists(path)
    local info, _ = utils.file_info(path)
    return info ~= nil
end

function find_cover(dir)
    -- make dir an absolute path
    if dir[1] ~= "/" then
        dir = utils.join_path(utils.getcwd(), dir)
    end

    for _, file in ipairs(cover_filenames) do
        local path = utils.join_path(dir, file)
        if file_exists(path) then
            return path
        end
    end

    return nil
end

function walk_api(api_path)
  local body = select(1, https.request(api_path[1]))
  for i, keys in ipairs(api_path) do
    if i > 1 then
      body = lunajson.decode(body)
      for _, key in ipairs(keys) do
        body = body[key]
      end
      msg.verbose(body)
      body = select(1, https.request(body))
    end
  end
  return body
end

function notify_current_media()
    local path = mp.get_property_native("path")

    if path ~= nil then
    local dir, file = utils.split_path(path)

    -- TODO: handle embedded covers and videos?
    -- potential options: mpv's take_screenshot, ffprobe/ffmpeg, ...
    -- hooking off existing desktop thumbnails would be good too
    local thumbnail = find_cover(dir)

    local title = file
    local origin = dir

    notify_media(title, origin, thumbnail)
    end
    socket.sleep(2)
    mp.observe_property("metadata", "string", notify_metadata_updated)
end

function notify_metadata_updated(name, data)
    msg.debug(name, data)
    local metadata = mp.get_property_native("metadata")
    if metadata then
        for i, v in ipairs(metadata) do msg.debug(i, v) end
        function tag(name)
            return metadata[string.upper(name)] or metadata[name]
        end

        local title = tag("title") or tag("icy-title") or ""
        local origin = tag("artist_credit") or tag("artist") or ""

        local album = tag("album")
        if album then
            origin = string.format("%s — %s", origin, album)
        end

        local year = tag("original_year") or tag("year")
        if year then
            origin = string.format("%s (%s)", origin, year)
        end

        local thumbnail = nil
        --[[
        config.json syntax:
        {
          "http://path/to/radio/station" :
          [
            "http://path/to/first/API/endpoint",
            ["json params", "to second", "API endpoint" ],
            ["json params", "to third", "API endpoint" ],
            ...
            ["json params", "to ", "art location" ]
          ]
        }
        --]]

        local f = io.open(os.getenv("HOME") .. "/.config/mpv/mpv-notify-send/config.json", "r")
        local config = lunajson.decode(f:read("*a"))
        f:close()
        msg.verbose(mp.get_property_native("path"))
        if config[mp.get_property_native("path")] ~= nil then
            thumbnail = "/tmp/mpv-notify-send.thumbnail"
            f = io.open(thumbnail, "w")
            f:write(walk_api(config[mp.get_property_native("path")]))
            f:close()
        end
        notify_media(title, origin, thumbnail)
    end
end

mp.register_event("file-loaded", notify_current_media)
