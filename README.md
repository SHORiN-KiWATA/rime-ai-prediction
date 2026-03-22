# rime-ai-prediction

rime雾凇拼音输入法的Ai候选词生成扩展。类似云拼音，平时正常输入，在遇到长难句或者生僻句的时候通过双击v键呼叫Ai对拼音进行处理。输入的时候不太需要考虑输入的拼音是否正确，大模型强大的预测功能会自动把误拼甚至乱序处理成正确的句子。对于句子中的英文词汇也能正常处理，甚至还能补充正确的空格和标点符号。

Ai可以是本地Ollama或LMStudio，也可以是API调用。

以下是无法正常输入，但Ai可以联想出来的例子：

包含英文词汇的输入

![](pictures/usevibecoding.gif)

歌词

![](pictures/cnag.gif)

古诗词

![](pictures/shici.gif)

超长句

![](pictures/steam.gif)

## 使用方法

1. 安装rime和雾凇拼音

    理论上对其他输入法方案也是生效的，但我只测试过雾凇拼音。安装方法可以看[ShorinArch_中文输入法](https://github.com/SHORiN-KiWATA/Shorin-ArchLinux-Guide/wiki/%E4%B8%AD%E6%96%87%E8%BE%93%E5%85%A5%E6%B3%95)

2. 复制lua脚本

    主要是三个文件：

    - `llm_config.lua` 进行大语言模型相关的配置

    - `rime.lua` 脚本主体

    - `rime_ice.custom.yaml` 自定义雾凇拼音配置（理论上可以是任意输入法方案），用于激活功能。

    把本仓库里的这三个文件复制粘贴到你的rime目录（fcitx5的话在`~/.local/share/fcitx5/rime`）。

3. 设置大语言模型

    需要编辑`llm_config.lua`设置你自己的`api_key`。

    例如从[aistudio.google.com](https://aistudio.google.com)获取gemini的api_key，或者从[platform.deepseek.com](https://platform.deepseek.com)获取deepseek的api_key，填写在对应的`profile`里。

    ```lua
    profiles = {
        
        deepseek = {
            name = "DeepSeek",
            api_url = "https://api.deepseek.com/chat/completions",
            api_key = "你的deepseek的Api_key",
            model = "deepseek-chat",
        },
        gemini = {
            name = "Gemini",
            api_url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
            api_key = "你的Geimini的Api_key",
            model = "gemini-3-flash-preview",
        },
        -- 其他Ai配置。。。。。
    },
    ```

    然后在配置文件顶部的`active_profile = "gemini",`切换要使用的配置（此处对应的是`gemini = {`的`gemini`名字，而不是`name`）。

    `model`可以设置使用的模型（如果有的话）。

    Ai选择方面，直接用AI公司提供的api体验最好。本地部署的Ai延迟最低，但是效果都很一般，注重隐私问题的话可以用本地部署的。脚本兼容推理模型（reasoning model），但是不建议使用推理模型，太慢太慢了。

4. 重启输入法

    最后重启输入法就生效了。输入一段拼音后按两次`v键`呼叫ai处理输入。

5. 其他配置

    编辑配置`llm_config.lua`无须重启输入法，保存后下次呼叫ai会自动读取修改后的配置文件。

    - `prompt = ""` 是发给ai的提示词。

    - `vocab_text`是自定义词库，分常用词和简拼映射两种，用于供ai参考。
