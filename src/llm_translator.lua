-- ==============================================================================
-- 文件名：llm_translator.lua
-- 功能：基于 LLM 的拼音长句整句翻译引擎 (支持 OpenAI / Anthropic 智能切换)
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

    local safe_prompt = string.gsub(Config.prompt or "", '"', '\\"')
    local safe_text = string.gsub(send_text, '"', '\\"')
    
    -- 智能识别 Anthropic (Claude) 协议
    local is_anthropic = string.find(current_ai.api_url, "anthropic") or string.find(current_ai.api_url, "messages$")
    local json_data = ""
    local auth_headers = ""

    if is_anthropic then
        -- Anthropic 格式: system 和 messages 是平级的，role 只有 user/assistant
        json_data = string.format(
            '{"model":"%s","system":"%s","messages":[{"role":"user","content":"%s"}],"temperature":%s,"max_tokens":%s}',
            current_ai.model, safe_prompt, safe_text, Config.temperature or 0.1, Config.max_tokens or 4000
        )
        auth_headers = string.format("-H 'x-api-key: %s' -H 'anthropic-version: 2023-06-01'", api_key)
    else
        -- OpenAI 兼容格式
        json_data = string.format(
            '{"model":"%s","messages":[{"role":"system","content":"%s"},{"role":"user","content":"%s"}],"temperature":%s,"max_tokens":%s}',
            current_ai.model, safe_prompt, safe_text, Config.temperature or 0.1, Config.max_tokens or 4000
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
        local clean = string.gsub(raw_content, "\\n", "")
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
