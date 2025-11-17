/*
    Ollama 本地实时翻译插件 for PotPlayer
    文件名示例: ollama.as

    说明：
    - 调用本地 Ollama HTTP 服务（默认 http://127.0.0.1:11434/v1/chat/completions）
    - 从 UI 的 Model Name 字段读取模型名称
    - 不需要 API Key（本地运行的 ollama 不需要）
    - 翻译提示词尽量简洁且为英文，要求模型仅输出翻译结果（无多余说明）
*/

// ----------------- 插件信息接口 -----------------
string GetTitle() {
    return "{$CP936=本地 Ollama 翻译$}{$CP0=Local Ollama Translate$}";
}

string GetVersion() {
    return "1.1";
}

string GetDesc() {
    return "{$CP936=使用本地 Ollama 模型的实时字幕翻译$}{$CP0=Real-time subtitle translation using local Ollama model$}";
}

string GetLoginTitle() {
    return "{$CP936=Ollama 模型配置$}{$CP0=Ollama Model Configuration$}";
}

string GetLoginDesc() {
    return "{$CP936=请输入 Ollama 模型名称$}{$CP0=Please enter the Ollama model name$}";
}

// 在 PotPlayer 登录对话框中显示的用户输入框文字
string GetUserText() {
    return "{$CP936=模型名称 当前: " + selected_model + "$}{$CP0=Model Name Current: " + selected_model + "$}";
}

// 无需密码，保持空
string GetPasswordText() {
    return "";
}

// ----------------- 全局变量 -----------------
string selected_model = "wangshenzhi/gemma2-9b-chinese-chat:latest"; // 默认模型，可被 UI 覆盖
string UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)";
string api_url = "http://127.0.0.1:11434/v1/chat/completions"; // 本地 Ollama 预设地址

// 支持语言表（简化，PotPlayer 会使用这个列表填充下拉）
array<string> LangTable =
{
    "Auto", "en", "zh", "zh-CN", "zh-TW", "ja", "ko", "fr", "de", "es", "ru", "it", "pt"
};

// 返回来源语言列表（Auto 为自动检测）
array<string> GetSrcLangs() {
    array<string> ret = LangTable;
    return ret;
}

// 返回目标语言列表
array<string> GetDstLangs() {
    array<string> ret = LangTable;
    return ret;
}

// ----------------- 登录 / 登出 -----------------
// 接收 UI 的 User 为模型名称，Pass 忽略（保持兼容）
string ServerLogin(string User, string Pass) {
    selected_model = User.Trim();
    if (selected_model.empty()) {
        HostPrintUTF8("{$CP936=模型名称未输入，请输入有效的模型名称（例如 wangshenzhi/gemma2-9b-chinese-chat:latest）。$}{$CP0=Model name not entered. Please enter a valid model name (e.g., wangshenzhi/gemma2-9b-chinese-chat:latest).$}\n");
        selected_model = "wangshenzhi/gemma2-9b-chinese-chat:latest";
        return "fail";
    }
    // 保存到临时存储以便重启后恢复
    HostSaveString("selected_model", selected_model);
    HostPrintUTF8("{$CP936=模型已设定: $}{$CP0=Model set: $}" + selected_model + "\n");
    return "200 ok";
}

void ServerLogout() {
    selected_model = "wangshenzhi/gemma2-9b-chinese-chat:latest";
    HostSaveString("selected_model", selected_model);
    HostPrintUTF8("{$CP936=已登出，模型已重置为默认值。$}{$CP0=Logged out and model reset to default.$}\n");
}

// ----------------- JSON 转义工具 -----------------
// 将字符串转为 JSON 字面量中的安全文本
string JsonEscape(const string &in input) {
    string output = input;
    output.replace("\\", "\\\\");
    output.replace("\"", "\\\"");
    output.replace("\n", "\\n");
    output.replace("\r", "\\r");
    output.replace("\t", "\\t");
    return output;
}

// ----------------- 翻译函数 -----------------
// Text     : 要翻译的文本（通常是 potplayer 实时字幕）
// SrcLang  : 传入时为来源语言代码或 "Auto"（可被修改为实际传回的编码标识）
// DstLang  : 目标语言代码（必填）
// 函数要求：仅返回翻译文本（不带任何额外说明）
string Translate(string Text, string &in SrcLang, string &in DstLang) {
    // 从临时存储读取已保存的模型名称（防止 potplayer 重启后丢失）
    selected_model = HostLoadString("selected_model", selected_model);

    if (Text.empty()) return "";

    // 若目标语言未指定或为 Auto，则直接返回空（PotPlayer UI 应要求选择目标语言）
    if (DstLang.empty() || DstLang == "Auto" || DstLang == "{$CP936=自动检测$}{$CP0=Auto Detect$}") {
        HostPrintUTF8("{$CP936=目标语言未指定，请在插件设定中选择目标语言。$}{$CP0=Target language not specified. Please choose a target language in plugin settings.$}\n");
        return "";
    }

    // 如果来源语言选为 Auto 或空，则不在提示中指定来源语言，让模型自动判定
    string src_clause = "";
    if (!SrcLang.empty() && SrcLang != "Auto") {
        src_clause = " from " + SrcLang;
    }

    // 构建 prompt：简短英文，要求模型仅输出翻译结果
    // 例： "Translate to zh: <text>\n\nOutput only the translated text."
    string short_prompt = "Translate" + src_clause + " to " + DstLang + ":\\n\\n" + Text + "\\n\\nOutput only the translated text.";

    // JSON 转义
    string escapedUser = JsonEscape(short_prompt);

    // 使用简单 system 指令来强化只输出翻译的要求
    string system_msg = "You are a translator. Output only the translated text without any extra explanation.";

    // 构建 Ollama /chat/completions 请求体
    string requestData = "{\"model\":\"" + selected_model + "\",\"messages\":[{\"role\":\"system\",\"content\":\"" + JsonEscape(system_msg) + "\"},{\"role\":\"user\",\"content\":\"" + escapedUser + "\"}],\"max_tokens\":2048}";

    // 发送 POST 请求到本地 Ollama
    string headers = "Content-Type: application/json";
    string response = HostUrlGetString(api_url, UserAgent, headers, requestData);

    if (response.empty()) {
        HostPrintUTF8("{$CP936=无法连接到本地 Ollama 服务，请确认服务在 http://127.0.0.1:11434 正常运行。$}{$CP0=Failed to connect to local Ollama service. Ensure it is running at http://127.0.0.1:11434.$}\n");
        return "";
    }

    // 解析 JSON 响应，支持常见结构 choices[0].message.content 或 outputs[0].content
    JsonReader Reader;
    JsonValue Root;
    string translatedText = "";

    if (!Reader.parse(response, Root)) {
        // 若无法解析，直接尝试截取简单情况（防御性）
        HostPrintUTF8("{$CP936=无法解析 Ollama 回应。回应内容: $}{$CP0=Failed to parse Ollama response. Response: $}" + response + "\n");
        return "";
    }

    // 优先处理 OpenAI 风格的 choices->message->content
    if (Root.isObject() && Root["choices"].isArray() && Root["choices"][0]["message"]["content"].isString()) {
        translatedText = Root["choices"][0]["message"]["content"].asString();
    }
    // 再处理某些 Ollama 会使用 outputs 或 text 的情况
    else if (Root.isObject() && Root["outputs"].isArray() && Root["outputs"][0]["content"].isString()) {
        translatedText = Root["outputs"][0]["content"].asString();
    }
    // 再试 choices[0].text
    else if (Root.isObject() && Root["choices"].isArray() && Root["choices"][0]["text"].isString()) {
        translatedText = Root["choices"][0]["text"].asString();
    }
    // 最后尝试直接取 root["text"]
    else if (Root.isObject() && Root["text"].isString()) {
        translatedText = Root["text"].asString();
    }

    // 若仍为空，返回空并输出错误日志
    if (translatedText.empty()) {
        HostPrintUTF8("{$CP936=未从 Ollama 回应中获取到翻译文本，请检查模型输出格式。$}{$CP0=No translated text found in Ollama response. Check model output format.$}\n");
        return "";
    }

    // 去掉首尾空白
    translatedText = translatedText.Trim();

    // 如果返回为多行，可以直接返回（PotPlayer 会显示）
    // 对于从右至左语言（如 ar/he/fa）PotPlayer 可能需要处理，这里不做特殊处理
    SrcLang = "UTF8";
    DstLang = "UTF8";

    // 仅返回翻译文本（插件要求）
    return translatedText;
}

// ----------------- 插件初始化 / 结束 -----------------
void OnInitialize() {
    HostPrintUTF8("{$CP936=Ollama 翻译插件已加载。$}{$CP0=Ollama translation plugin loaded.$}\n");
    // 尝试从临时存储恢复模型名称
    selected_model = HostLoadString("selected_model", selected_model);
    if (!selected_model.empty()) {
        HostPrintUTF8("{$CP936=已载入模型：$}{$CP0=Loaded model: $}" + selected_model + "\n");
    }
}

void OnFinalize() {
    HostPrintUTF8("{$CP936=Ollama 翻译插件已卸载。$}{$CP0=Ollama translation plugin unloaded.$}\n");
}