local mr = require('mason-registry')

local SETTINGS = {
	ensure_installed = {},
	auto_update = false,
	start_delay = 0,
}

local function dump(o)
	if type(o) == 'table' then
		local s = '{ '
		for k, v in pairs(o) do
			if type(k) ~= 'number' then
				k = '"' .. k .. '"'
			end
			s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
		end
		return s .. '} '
	else
		return tostring(o)
	end
end

local function getKeys(tab)
	if tab == nil then
		return nil
	end
	local keyset = {}

	for k, _ in pairs(tab) do
		keyset[k] = true
	end
	return keyset
end

local function tableToKeys(tab)
	local keyset = {}
	for k, _ in pairs(tab) do
		table.insert(keyset, k)
	end
	return keyset
end

-- local function merge(t1, t2)
-- 	for k, v in pairs(t2) do
-- 		if (type(v) == 'table') and (type(t1[k] or false) == 'table') then
-- 			merge(t1[k], t2[k])
-- 		else
-- 			t1[k] = v
-- 		end
-- 	end
-- 	return t1
-- end

local function lookup(t)
	local tools = {}
	local mappings = require('mason-null-ls.mappings')
	for source, _ in pairs(t) do
		local wantedTools = mappings[source] or {}
		for _, tool in pairs(wantedTools) do
			tools[tool] = true
		end
	end
	return tools
end

local setup = function(settings)
	local t = {}
	t = vim.tbl_deep_extend('force', t, getKeys(require('null-ls.builtins').diagnostics))
	t = vim.tbl_deep_extend('force', t, getKeys(require('null-ls.builtins').formatting))
	t = vim.tbl_deep_extend('force', t, getKeys(require('null-ls.builtins').code_actions))
	t = vim.tbl_deep_extend('force', t, getKeys(require('null-ls.builtins').completion))
	t = vim.tbl_deep_extend('force', t, getKeys(require('null-ls.builtins').hover))
	local tools = tableToKeys(lookup(t))
	print(dump(tools))
	SETTINGS = vim.tbl_deep_extend('force', SETTINGS, settings)
	SETTINGS.ensure_installed = tools
	vim.validate({
		ensure_installed = { SETTINGS.ensure_installed, 'table', true },
		auto_update = { SETTINGS.auto_update, 'boolean', true },
		start_delay = { SETTINGS.start_delay, 'number', true },
	})
end

local show = function(msg)
	vim.schedule_wrap(print(string.format('[mason-null-ls] %s', msg)))
end

local show_error = function(msg)
	vim.schedule_wrap(vim.api.nvim_err_writeln(string.format('[mason-null-ls] %s', msg)))
end

local do_install = function(p, version, on_close)
	if version ~= nil then
		show(string.format('%s: updating to %s', p.name, version))
	else
		show(string.format('%s: installing', p.name))
	end
	p:once('install:success', function()
		show(string.format('%s: successfully installed', p.name))
	end)
	p:once('install:failed', function()
		show_error(string.format('%s: failed to install', p.name))
	end)
	p:install({ version = version }):once('closed', vim.schedule_wrap(on_close))
end

local check_install = function(force_update)
	local completed = 0
	local total = vim.tbl_count(SETTINGS.ensure_installed)
	local on_close = function()
		completed = completed + 1
		if completed >= total then
			vim.api.nvim_exec_autocmds('User', {
				pattern = 'MasonToolsUpdateCompleted',
				-- 'data' doesn't work with < 0.8.0
				-- data = { packages = SETTINGS.ensure_installed },
			})
		end
	end
	for _, item in ipairs(SETTINGS.ensure_installed or {}) do
		local name, version, auto_update
		if type(item) == 'table' then
			name = item[1]
			version = item.version
			auto_update = item.auto_update
		else
			name = item
		end
		local p = mr.get_package(name)
		if p:is_installed() then
			if version ~= nil then
				p:get_installed_version(function(ok, installed_version)
					if ok and installed_version ~= version then
						do_install(p, version, on_close)
					else
						completed = completed + 1
					end
				end)
			elseif
				force_update or (force_update == nil and (auto_update or (auto_update == nil and SETTINGS.auto_update)))
			then
				p:check_new_version(function(ok, version)
					if ok then
						do_install(p, version.latest_version, on_close)
					else
						completed = completed + 1
					end
				end)
			else
				completed = completed + 1
			end
		else
			do_install(p, version, on_close)
		end
	end
end

return {
	check_install = check_install,
	setup = setup,
}
