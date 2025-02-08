------------------ PRIVATE IMPLEMENTATION

-- For a given path to a sound file, returns the command to play the sound on Mac.
---@param path string # Path to a sound file.
---@return string command # A MacOs command to play the sound file with for the given path.
local function get_sound_playing_cmd_for_mac(path)
  return "afplay " .. path
end

-- For a given path to a sound file, returns the command to play the sound on Linux.
---@param path string # Path to a sound file.
---@return string command # A Linux command to play the sound file with for the given path.
local function get_sound_playing_cmd_for_linux(path)
  return "aplay " .. path
end

-- For a given path to a sound file, returns the command to play the sound on Windows.
---@param path string # Path to a sound file.
---@return string command # A Windows command to play the sound file with for the given path.
local function get_sound_playing_cmd_for_windows(path)
  return "powershell -c (New-Object Media.SoundPlayer '" .. path .. "').PlaySync();"
end

-- Determines the correct function to be used to compose the sound-playing command
-- for the given OS.
---@return fun(path: string) compose_command_fn # An OS-specific function to create sound-playing commands.
local function get_command_composing_fn()
  local operating_system = jit.os

  if operating_system == "OSX" then
    return get_sound_playing_cmd_for_mac
  elseif operating_system == "Linux" then
    return get_sound_playing_cmd_for_linux
  elseif operating_system == "Windows" then
    return get_sound_playing_cmd_for_windows
  end

  error("OS couldn't be determined!")
end

---@class SoundPlayer
---@field package compose_command fun(path: string): string
---@field public play_sound fun(self: SoundPlayer, path: string): nil

---@type SoundPlayer
local SoundPlayerSingleton = {
  compose_command = get_command_composing_fn(),
  play_sound = function(self, path)
    local command = self.compose_command(path)

    -- Plays the sound in a non-blocking way.
    vim.fn.jobstart(command)
  end,
}

----------------------- MODULE DEFINITION
local M = {}

----------------------- PUBLIC MODULE API

---@type SoundPlayer
M.player = SoundPlayerSingleton

------------------------------ MODULE END
return M
