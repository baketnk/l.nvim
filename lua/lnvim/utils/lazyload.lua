function LazyLoad(module_name)
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
	return M
end

return LazyLoad
