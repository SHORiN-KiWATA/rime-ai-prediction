-- ==============================================================================
-- 功能：Rime LLM 长句转换器 
-- ==============================================================================

local function load_config()
    -- 智能获取路径，兼容各种 Linux 发行版的新老路径规范
    local user_dir = rime_api and rime_api.get_user_data_dir and rime_api.get_user_data_dir()
    if not user_dir or user_dir == "" then
        user_dir = os.getenv("HOME") .. "/.local/share/fcitx5/rime"
    end
    local config_path = user_dir .. "/llm_config.lua"

    local f = io.open(config_path, "r")
    if not f then return nil, "找不到文件: " .. config_path end
    f:close()

    local chunk, err = loadfile(config_path)
    if not chunk then return nil, "语法错误: " .. tostring(err) end
    
    local success, cfg = pcall(chunk)
    if success and type(cfg) == "table" then return cfg, nil end
    return nil, "格式错误"
end

function llm_translator(input, seg, env)
    -- 1. 严格拦截：如果输入不是 vv 结尾，立刻放行，绝不卡顿
    if not string.match(input, "vv$") then return end
    
    -- 💡 2. 内部探针：只要你输入 testvv，强行弹出成功标志！(证明 YAML 和 Lua 挂载正常)
    if input == "testvv" then
        yield(Candidate("llm", seg.start, seg._end, "✅ 3文件版引擎连通成功!", "连通测试"))
        return
    end

    local send_text = string.sub(input, 1, -3)
    if #send_text == 0 then return end

    -- 3. 读取配置
    local Config, err_msg = load_config()
    if not Config then
        yield(Candidate("llm", seg.start, seg._end, send_text, "❌ 配置读取失败: " .. tostring(err_msg)))
        return
    end

    local current_ai = Config.profiles and Config.profiles[Config.active_profile]
    if not current_ai then
        yield(Candidate("llm", seg.start, seg._end, send_text, "❌ 找不到节点: " .. tostring(Config.active_profile)))
        return
    end

    local api_key = current_ai.api_key
    if not api_key or api_key == "" then
        yield(Candidate("llm", seg.start, seg._end, send_text, "❌ API Key 为空"))
        return
    end

    -- 4. 构建请求 (去除了高危的 Pkill 系统调用，防止沙盒拦截)
    local safe_prompt = string.gsub(Config.prompt or "", '"', '\\"')
    local safe_text = string.gsub(send_text, '"', '\\"')
    
    local json_data = string.format(
        '{"model":"%s","messages":[{"role":"system","content":"%s"},{"role":"user","content":"%s"}],"temperature":%s,"max_tokens":%s}',
        current_ai.model, safe_prompt, safe_text, Config.temperature or 0.1, Config.max_tokens or 1000
    )
    local safe_json = string.gsub(json_data, "'", "'\\''")
    
    local curl_cmd = string.format(
        "curl -sS --connect-timeout %s --max-time %s -X POST %s -H 'Content-Type: application/json' -H 'Authorization: Bearer %s' -d '%s' 2>&1",
        Config.connect_timeout or 2, Config.max_time or 15, current_ai.api_url, api_key, safe_json
    )

    local handle = io.popen(curl_cmd)
    if not handle then
        yield(Candidate("llm", seg.start, seg._end, send_text, "❌ 网络组件 io.popen 崩溃"))
        return
    end
    local response = handle:read("*a")
    handle:close()

    -- 5. 解析并输出
    if not response or response == "" then
        yield(Candidate("llm", seg.start, seg._end, send_text, "⏳ 请求超时无响应"))
        return
    end

    local raw_content = string.match(response, '"content":%s*"([^"]+)"')
    if raw_content then
        local clean = string.gsub(raw_content, "\\n", "")
        clean = string.gsub(clean, "<think>.-</think>", "")
        clean = string.gsub(clean, "^%s*(.-)%s*$", "%1")
        yield(Candidate("llm", seg.start, seg._end, clean, "✨ " .. (current_ai.name or "AI")))
    else
        local short_err = string.sub(response, 1, 40)
        short_err = string.gsub(short_err, "[\r\n]", " ")
        yield(Candidate("llm", seg.start, seg._end, send_text, "❌ " .. short_err))
    end
end
