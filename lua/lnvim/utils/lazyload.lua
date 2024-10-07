_G.lazyload = {}

function LazyLoad(module_name)
	if _G.lazyload[module_name] then
		return _G.lazyload[module_name]
	end
	local M = { init = false }
	setmetatable(M, {
		__index = function(t, k)
			if t["init"] == false then
				t["module"] = require(module_name)
				t["init"] = true
			end
			return rawget(t["module"], k)
		end,
	})
	vim.print("created new lazyload module " .. module_name)
	_G.lazyload[module_name] = M
	return M
end

return LazyLoad
