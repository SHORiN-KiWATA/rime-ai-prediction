-- ==============================================================================
-- 文件名：llm_translator.lua
-- 功能：基于 LLM 的拼音长句整句翻译引擎 (支持 OpenAI / Anthropic / 思考模式智能切换)
-- ==============================================================================

local function load_config()
    local home = os.getenv("HOME")
    if not home then return nil, "系统环境变量 HOME 无法读取" end

    local config_path = home .. "/.config/rime-llm-translator/config.lua"

    local f = io.open(config_path, "r")
    if not f then 
        return nil, "未生成: " .. config_path .. " (请运行 rime-llm-config 并点击 Save)" 
    end
    f:close()

    local chunk, err = loadfile(config_path)
    if not chunk then return nil, "配置语法错误: " .. tostring(err) end
    
    local success, cfg = pcall(chunk)
    if success and type(cfg) == "table" then return cfg, nil end
    return nil, "配置格式错误"
end

-- 将包含换行、双引号等内容的 Lua 字符串安全转化为 JSON 合法字符串
local function escape_json(str)
    if not str then return "" end
    local s = string.gsub(str, "\\", "\\\\")
    s = string.gsub(s, '"', '\\"')
    s = string.gsub(s, "\n", "\\n")
    s = string.gsub(s, "\r", "\\r")
    s = string.gsub(s, "\t", "\\t")
    return s
end

local function translator(input, seg, env)
    local Config, err_msg = load_config()
    if not Config then
        if string.match(input, "vv$") then
            yield(Candidate("llm", seg.start, seg._end, string.sub(input, 1, -3), "❌ " .. tostring(err_msg)))
        end
        return
    end

    local trigger = Config.ai_trigger or "vv"
    local trigger_len = string.len(trigger)
    
    if string.sub(input, -trigger_len) ~= trigger then return end

    if input == ("test" .. trigger) then
        yield(Candidate("llm", seg.start, seg._end, "✅ rime-llm-translator 挂载成功!", "连通测试"))
        return
    end

    local send_text = string.sub(input, 1, -trigger_len - 1)
    if #send_text == 0 then return end

    local current_ai = Config.profiles and Config.profiles[Config.active_profile]
    if not current_ai then
        yield(Candidate("llm", seg.start, seg._end, send_text, "❌ 找不到节点: " .. tostring(Config.active_profile)))
        return
    end

    local api_key = current_ai.api_key
    if not api_key or api_key == "" then
        yield(Candidate("llm", seg.start, seg._end, send_text, "❌ API Key 为空，请配置"))
        return
    end

    -- 通过全新的 escape_json 函数进行终极安全处理
    local safe_prompt = escape_json(Config.prompt or "")
    local safe_text = escape_json(send_text)
    
    local url_lower = string.lower(current_ai.api_url)
    local model_lower = string.lower(current_ai.model)

    -- 智能识别厂商协议
    local is_anthropic = string.find(url_lower, "anthropic") or string.find(url_lower, "messages$")
    local is_deepseek = (string.find(url_lower, "deepseek") or string.find(model_lower, "deepseek")) and not string.find(model_lower, "chat")
    local is_gemini = string.find(url_lower, "generativelanguage") or string.find(model_lower, "gemini")
    local is_mimo = (string.find(url_lower, "xiaomimimo") or string.find(model_lower, "mimo")) and not string.find(model_lower, "tts")
    
    local runtime_model = current_ai.model
    local thinking_json = ""
    local req_max_tokens = Config.max_tokens or 4000
    
-- 思考模式处理逻辑
    local is_thinking_enabled = false
    local effort = "high"
    
    local mode_str = current_ai.thinking_mode or ""
    if mode_str ~= "" and not string.find(mode_str, "Disabled") and not string.find(mode_str, "关闭") then
        is_thinking_enabled = true
        if string.find(mode_str, "Low") or string.find(mode_str, "低") then effort = "low"
        elseif string.find(mode_str, "Medium") or string.find(mode_str, "中") then effort = "medium"
        elseif string.find(mode_str, "Max") then effort = "max" -- [修复 2] 补充匹配 Max 强度，适配 DeepSeek v4
        end
    end

if is_thinking_enabled then
        if is_anthropic then
            local budget = math.floor(req_max_tokens * 0.8)
            if budget < 1024 then budget = 1024 end
            if req_max_tokens <= budget then req_max_tokens = budget + 100 end
            thinking_json = string.format(',"thinking": {"type": "enabled", "budget_tokens": %d}', budget)
        elseif is_deepseek then
            runtime_model = string.gsub(runtime_model, "deepseek%-chat", "deepseek-reasoner")
            thinking_json = string.format(',"thinking":{"type":"enabled"},"reasoning_effort":"%s"', effort)
        elseif is_mimo then
            thinking_json = ',"thinking":{"type":"enabled"}'
        else
            -- Gemini 等使用 reasoning_effort
            thinking_json = string.format(',"reasoning_effort":"%s"', effort)
        end
    else
        if is_deepseek then
            runtime_model = string.gsub(runtime_model, "deepseek%-reasoner", "deepseek-chat")
            thinking_json = ',"thinking":{"type":"disabled"}'
        elseif is_mimo then
            thinking_json = ',"thinking":{"type":"disabled"}'
        elseif is_gemini then
            thinking_json = ',"reasoning_effort":"low"'
        end
    end

    local json_data = ""
    local auth_headers = ""

    if is_anthropic then
        json_data = string.format(
            '{"model":"%s","system":"%s","messages":[{"role":"user","content":"%s"}],"temperature":%s,"max_tokens":%s%s}',
            runtime_model, safe_prompt, safe_text, Config.temperature or 0.1, req_max_tokens, thinking_json
        )
        auth_headers = string.format("-H 'x-api-key: %s' -H 'anthropic-version: 2023-06-01'", api_key)
    else
        json_data = string.format(
            '{"model":"%s","messages":[{"role":"system","content":"%s"},{"role":"user","content":"%s"}],"temperature":%s,"max_tokens":%s%s}',
            runtime_model, safe_prompt, safe_text, Config.temperature or 0.1, req_max_tokens, thinking_json
        )
        auth_headers = string.format("-H 'Authorization: Bearer %s'", api_key)
    end
    
    local safe_json = string.gsub(json_data, "'", "'\\''")
    local curl_cmd = string.format(
        "curl -sSL --connect-timeout %s --max-time %s -X POST %s -H 'Content-Type: application/json' %s -d '%s' 2>&1",
        Config.connect_timeout or 2.0, Config.max_time or 30.0, current_ai.api_url, auth_headers, safe_json
    )

    local handle = io.popen(curl_cmd)
    if not handle then
        yield(Candidate("llm", seg.start, seg._end, send_text, "❌ 网络组件 io.popen 崩溃"))
        return
    end
    local response = handle:read("*a")
    handle:close()
    -- ==========================================
    -- 🐛 [Debug 模式] 触发式日志记录
    -- ==========================================
    -- 只有当 Python 创建了这把“钥匙”，Lua 才会消耗 I/O 去写日志
    local debug_trigger = io.open("/tmp/.rime_llm_debug_active", "r")
    if debug_trigger then
        debug_trigger:close()
        local debug_file = io.open("/tmp/rime_llm_debug.log", "a")
        if debug_file then
            debug_file:write("========== " .. os.date("%Y-%m-%d %H:%M:%S") .. " ==========\n")
            debug_file:write("【节点模型】 " .. (current_ai.name or "Unknown") .. " (" .. runtime_model .. ")\n")
            debug_file:write("【发出的 JSON】\n" .. json_data .. "\n\n")
            debug_file:write("【收到的 Raw 返回】\n" .. (response or "nil") .. "\n")
            debug_file:write("==================================================\n\n")
            debug_file:close()
        end
    end
    if not response or response == "" then
        yield(Candidate("llm", seg.start, seg._end, send_text, "⏳ 请求超时无响应"))
        return
    end

    local safe_response = string.gsub(response, '\\"', '__QUOTE__')
    local raw_content = nil

    if is_anthropic then
        raw_content = string.match(safe_response, '"text":%s*"([^"]+)"')
    else
        raw_content = string.match(safe_response, '"content":%s*"([^"]+)"')
    end
    
    if raw_content then
        raw_content = string.gsub(raw_content, "__QUOTE__", '"')
        local clean = string.gsub(raw_content, "\\n", "\n")
        clean = string.gsub(clean, "<think>.-</think>", "")
        clean = string.gsub(clean, "<think>.*", "")
        clean = string.gsub(clean, "^%s*(.-)%s*$", "%1")
        
        yield(Candidate("llm", seg.start, seg._end, clean, "✨ " .. (current_ai.name or "AI")))
    else
        local short_err = string.sub(response, 1, 40)
        short_err = string.gsub(short_err, "[\r\n]", " ")
        yield(Candidate("llm", seg.start, seg._end, send_text, "❌ 解析失败: " .. short_err))
    end
end

return translator
