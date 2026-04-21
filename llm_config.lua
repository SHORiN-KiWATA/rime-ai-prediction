-- =========================================================
-- 文件名：llm_config.lua
-- 存放位置：~/.local/share/fcitx5/rime/
-- =========================================================

return {
    -- ==========================================
    -- 🎛️ 1. 核心大模型切换
    -- ==========================================
    active_profile = "deepseek",

    -- ==========================================
    -- 🌐 2. LLM 后端配置库
    -- ==========================================
    profiles = {
        deepseek = {
            name = "DeepSeek",
            api_url = "https://api.deepseek.com/chat/completions",
            api_key = "【你的apikey】",
            model = "deepseek-chat",
        },
        gemini = {
            name = "Gemini",
            api_url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
            api_key = "【你的apikey】",
            model = "gemini-3-flash-preview",
        },
        xiaomi = {
            name = "Xiaomi",
            api_url = "https://api.xiaomimimo.com/v1/chat/completions",
            api_key = "【你的apikey】",
            model = "mimo-v2-omni",
        },
        minimax = {
            name = "Minimax",
            api_url = "https://api.minimaxi.com/v1/chat/completions",
            api_key = "【你的apikey】",
            model = "MiniMax-M2.7",
        },
        openrouter = {
            name = "OpenRouter",
            api_url = "https://openrouter.ai/api/v1/chat/completions",
            api_key = "【你的apikey】",
            model = "minimax-m2.7",
        },
        ollama = {
            name = "Ollama",
            api_url = "http://192.168.0.13:11434/v1/chat/completions",
            api_key = "ollama",
            model = "qwen3-coder-next:q4_K_M",
        },
        lmstudio = {
            name = "LMStudio",
            api_url = "http://localhost:1234/v1/chat/completions",
            api_key = "lm-studio",
            model = "local-model",
        },
    },

    -- ==========================================
    -- 🚀 3. 基础功能配置
    -- ==========================================
    ai_trigger = "vv",
    
    prompt = "你是一个智能拼音输入法引擎，熟知中华文化、二次元文化、网络文化等常见输入内容。你的职责是把用户的拼音转化为流畅、通顺、合理的句子。你你要识别出拼音中的错输、乱序等问题，通过切分用户的拼音推理出正确的句子。注意几点：1. 准确还原语境中的英文词汇。2. 高度重视【纯首字母简拼】（如mrfz=明日方舟）。3. 重视【前后鼻音】区分，用户可能发给你错误的前后鼻音，你要通过前后的拼音上下文做出正确的判断。严格遵守：绝对不要输出解释、思考内容、拼音或双引号！",

    -- ==========================================
    -- ⚙️ 4. API 请求参数
    -- ==========================================
    max_tokens = 4000,
    temperature = 0.1,
    connect_timeout = 2.0, 
    max_time = 30.0,

    -- ==========================================
    -- 📚 5. AI 输入法专属外挂词库
    -- ==========================================
    vocab_text = [[
# -------- 常用英文/网络黑话 --------
vibecoding
rime
bootloader
wm
de

# -------- 首字母简拼/拼音缩写映射 --------
mrfz=明日方舟
yyds=永远的神
srwc=是人我吃

    ]]
}
