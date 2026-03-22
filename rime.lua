-- ==============================================================================
-- 功能：Rime LLM 长句转换器 (修复瞬间报错、增强 JSON 转义、透传底层错误)
-- ==============================================================================

local LLM_Cache = { input = "", text = "", comment = "" }
local config_file_path = os.getenv("HOME") .. "/.local/share/fcitx5/rime/llm_config.lua"

local function load_config()
    local f = io.open(config_file_path, "r")
    if not f then return nil end
    f:close()

    local chunk = loadfile(config_file_path)
    if chunk then
        local success, user_config = pcall(chunk)
        if success and type(user_config) == "table" then
            return user_config
        end
    end
    return nil
end

local function parse_vocab_string(vocab_text)
    if not vocab_text or vocab_text == "" then return "" end
    local valid_lines = {}
    for line in string.gmatch(vocab_text, "[^\r\n]+") do
        line = string.gsub(line, "^%s*(.-)%s*$", "%1")
        if line ~= "" and string.sub(line, 1, 1) ~= "#" then
            table.insert(valid_lines, line)
        end
    end
    if #valid_lines == 0 then return "" end
    return table.concat(valid_lines, ", ")
end

function llm_translator(input, seg, env)
    local Config = load_config()
    if not Config then return end

    if not string.match(input, "^[a-z][a-z.,?'!:%-]*$") then return end
    local trigger_len = string.len(Config.ai_trigger)
    if string.sub(input, -trigger_len) ~= Config.ai_trigger then return end

    local send_text = string.sub(input, 1, - (trigger_len + 1))
    if #send_text < 1 then return end

    local active_key = Config.active_profile
    local current_ai = Config.profiles and Config.profiles[active_key]
    
    if not current_ai then
        yield(Candidate("llm_pinyin", seg.start, seg._end, send_text, "❌ 找不到配置: " .. tostring(active_key)))
        return
    end

    local ai_name = current_ai.name or "AI"
    local api_url = current_ai.api_url
    local api_key = current_ai.api_key
    local model_name = current_ai.model

    if not api_key or api_key == "" or string.find(api_key, "你的真实") then
        yield(Candidate("llm_pinyin", seg.start, seg._end, send_text, "❌ 请填写 " .. ai_name .. " 的 Key"))
        return
    end

    if input == LLM_Cache.input then
        yield(Candidate("llm_pinyin", seg.start, seg._end, LLM_Cache.text, LLM_Cache.comment))
        return
    end

    -- ==========================================
    -- 🚀 构造网络请求 (极度安全版)
    -- ==========================================
    local active_vocab = parse_vocab_string(Config.vocab_text)
    local vocab_hint = ""
    if active_vocab ~= "" then vocab_hint = "。以下是你可以参考的用户自定词库：" .. active_vocab end

    local prompt_system = Config.prompt .. vocab_hint
    
    -- 💡 修复 1：将系统提示词也进行 JSON 安全转义
    local safe_prompt_system = string.gsub(prompt_system, "\\", "\\\\")
    safe_prompt_system = string.gsub(safe_prompt_system, '"', '\\"')

    local safe_user_content = string.gsub(send_text, "\\", "\\\\")
    safe_user_content = string.gsub(safe_user_content, '"', '\\"')

    local json_data = string.format(
        '{"model":"%s","messages":[{"role":"system","content":"%s"},{"role":"user","content":"%s"}],"temperature":%s,"max_tokens":%s}',
        model_name, safe_prompt_system, safe_user_content, Config.temperature, Config.max_tokens
    )
    
    local safe_json_data = string.gsub(json_data, "'", "'\\''")
    
    -- 💡 修复 2：将 safe_json_data 改用字符串拼接 (..) 注入，彻底杜绝输入带 % 号引发的 Lua string.format 崩溃
    local curl_cmd = string.format(
        "curl -sS --connect-timeout %s --max-time %s -X POST %s -H 'Content-Type: application/json' -H 'Authorization: Bearer %s' -d ",
        Config.connect_timeout, Config.max_time, api_url, api_key
    ) .. "'" .. safe_json_data .. "' 2>&1"

    os.execute('pkill -f "curl.*chat/completions" 2>/dev/null')

    local handle = io.popen(curl_cmd)
    if not handle then return end
    local response = handle:read("*a")
    handle:close()

    -- ==========================================
    -- 🛠️ 结果解析与动态名称透传
    -- ==========================================
    if not response or response == "" then
        local err_label = "⏳ " .. ai_name .. " 超时"
        LLM_Cache = { input = input, text = send_text, comment = err_label }
        yield(Candidate("llm_pinyin", seg.start, seg._end, send_text, err_label))
        return
    end

    -- 💡 修复 3：将大模型返回的转义双引号提前干掉，防止 Lua 正则匹配被半路截断
    local safe_response = string.gsub(response, '\\"', '”')
    local raw_content = string.match(safe_response, '"content":%s*"([^"]+)"')

    if raw_content and raw_content ~= "" then
        local clean_result = string.gsub(raw_content, "\\n", "")
        clean_result = string.gsub(clean_result, "<think>.-</think>", "")
        clean_result = string.gsub(clean_result, "[\r\n\t]", "") 
        clean_result = string.gsub(clean_result, "^%s*(.-)%s*$", "%1")

        if clean_result ~= "" then
            local success_label = "✨ " .. ai_name
            LLM_Cache = { input = input, text = clean_result, comment = success_label }
            yield(Candidate("llm_pinyin", seg.start, seg._end, clean_result, success_label))
        end
    else
        -- 💡 修复 4：透传真实报错！不要只显示冷冰冰的 "错误"
        local err_msg = string.match(response, '"message":%s*"([^"]+)"')
        if err_msg then
            local short_err = string.sub(err_msg, 1, 50) -- 增加截取长度，方便你排错
            local err_label = "⚠️ " .. ai_name .. ": " .. short_err
            LLM_Cache = { input = input, text = send_text, comment = err_label }
            yield(Candidate("llm_pinyin", seg.start, seg._end, send_text, err_label))
        else
            local short_err = string.sub(response, 1, 50)
            short_err = string.gsub(short_err, "[\r\n]", " ")
            local err_label = "❌ " .. ai_name .. " 错误: " .. short_err
            LLM_Cache = { input = input, text = send_text, comment = err_label }
            yield(Candidate("llm_pinyin", seg.start, seg._end, send_text, err_label))
        end
    end
end
