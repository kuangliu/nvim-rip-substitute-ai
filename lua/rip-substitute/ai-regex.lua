local M = {}
local u = require("rip-substitute.utils")
--------------------------------------------------------------------------------

local SYSTEM_PROMPT = [[You are a regex conversion tool. Convert the user's natural language description into a valid regex pattern for use with ripgrep (PCRE2 syntax).

Rules:
- Return ONLY the raw regex pattern. Nothing else.
- No markdown formatting, no code fences, no quotes, no explanation.
- Use PCRE2-compatible syntax (supports lookaheads, lookbehinds, backreferences).
- If the input is already a valid regex, return it unchanged.
- Do not include delimiters (no leading/trailing slashes).
- Do not include flags (like /g, /i, /m) as part of the regex.
- If you cannot produce a regex, return the input unchanged.]]

---@param naturalLanguage string
---@param callback fun(regex: string|nil, errmsg: string|nil)
function M.convertToRegex(naturalLanguage, callback)
	local config = require("rip-substitute.config").config.aiRegex

	-- Guard: empty input
	naturalLanguage = vim.trim(naturalLanguage)
	if naturalLanguage == "" then
		callback(nil, "Empty search input.")
		return
	end

	-- Guard: no API key configured
	if config.apiKey == "" then
		callback(nil, "AI regex not configured. Set 'aiRegex.apiKey' in plugin config.")
		return
	end

	-- Build request body
	local body = {
		model = config.model,
		messages = {
			{ role = "system", content = SYSTEM_PROMPT },
			{ role = "user", content = naturalLanguage },
		},
		max_tokens = 500,
		temperature = 0,
		thinking = { type = "disabled" },
	}

	local curlArgs = {
		"curl",
		"--silent",
		"--show-error",
		"--max-time",
		"15",
		"--request",
		"POST",
		"--header",
		"Authorization: Bearer " .. config.apiKey,
		"--header",
		"Content-Type: application/json",
		"--data",
		vim.json.encode(body),
		config.baseUrl .. "/chat/completions",
	}

	u.notify("Converting natural language to regex...")

	vim.system(curlArgs, {}, function(out)
		vim.schedule(function()
			-- Curl error
			if out.code ~= 0 then
				local errMsg = ("AI request failed (exit=%d):\n%s"):format(
					out.code, out.stderr or "(no stderr)")
				u.notify(errMsg, "error")
				callback(nil, errMsg)
				return
			end

			-- Parse JSON response
			local ok, response = pcall(vim.json.decode, out.stdout)
			if not ok then
				u.notify("AI response parse failed.", "error")
				callback(nil, "Failed to parse API response")
				return
			end

			-- API-level error
			if response.error then
				local errMsg = response.error.message or response.error.code
					or "Unknown API error"
				u.notify("AI API error:\n" .. errMsg, "error")
				callback(nil, errMsg)
				return
			end

			-- Extract regex from response
			local content = response.choices
				and response.choices[1]
				and response.choices[1].message
				and response.choices[1].message.content

			content = vim.trim(content or "")
			if content == "" then
				u.notify("AI returned no content.", "error")
				callback(nil, "AI returned empty response")
				return
			end

			callback(content, nil)
		end)
	end)
end

--------------------------------------------------------------------------------
return M
