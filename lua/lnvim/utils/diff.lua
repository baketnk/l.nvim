local M = {}

local function run_command(cmd)
    local handle, err = io.popen(cmd)
    if err then
      vim.notify(err, vim.log.ERROR)
    end
    if not handle then
      vim.notify("no file handle for "+cmd, vim.log.ERROR)
      return nil
    end
    local result = handle:read("*a")
    handle:close()
    return result
end

function M.applyDiff(originalContent, diffText)
    -- Write original content to a temporary file
    local orig_file = os.tmpname()
    local diff_file = os.tmpname()
    local f, err = io.open(orig_file, "w")
    if err or not f then
      vim.notify(vim.inspect(err), vim.log.ERROR)
      return
    end
    f:write(originalContent)
    f:close()

    -- Write diff to a temporary file
    f, err = io.open(diff_file, "w")
    if err or not f then
      vim.notify(vim.inspect(err), vim.log.ERROR)
      return
    end
    f:write(diffText)
    f:close()

    -- Apply patch
    local cmd = string.format("patch -u %s %s", orig_file, diff_file)
    run_command(cmd)

    -- Read patched content
    f, err = io.open(orig_file, "r")
    if err or not f then
      vim.notify(vim.inspect(err), vim.log.ERROR)
      return
    end
    local result = f:read("*all")
    f:close()

    -- Clean up temporary files
    os.remove(orig_file)
    os.remove(diff_file)

    return result
end

return M
