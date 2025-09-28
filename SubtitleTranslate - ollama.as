/*
    Ollama 本地实时翻译插件 for PotPlayer
    文件名示例: ollama.as

    说明：
    - 调用本地 Ollama HTTP 服务（默认 http://127.0.0.1:11434/v1/chat/completions）
    - 从 UI 的 Model Name 字段读取模型名称（模式参照 PotPlayer 插件的 $CP0=... 语法）
    - 不需要 API Key（本地运行的 ollama 不需要）
    - 翻译提示词尽量简洁且为英文，要求模型仅输出翻译结果（无多余说明）
    - 注释全部为中文
*/

// ----------------- 插件信息接口 -----------------
string GetTitle() {
    return "{$CP949=本地 Ollama 翻譯$}{$CP950=本地 Ollama 翻譯$}{$CP0=Local Ollama Translate$}";
}

string GetVersion() {
    return "1.0";
}

string GetDesc() {
    return "{$CP949=使用本地 Ollama 模型的實時字幕翻譯$}{$CP950=使用本地 Ollama 模型的實時字幕翻譯$}{$CP0=Real-time subtitle translation using local Ollama model$}";
}

string GetLoginTitle() {
    return "{$CP949=Ollama 模型配置$}{$CP950=Ollama 模型配置$}{$CP0=Ollama Model Configuration$}";
}

string GetLoginDesc() {
    return "{$CP949=請在上方輸入 Ollama 模型名稱（例如：wangshenzhi/gemma2-9b-chinese-chat:latest）$}{$CP950=請在上方輸入 Ollama 模型名稱（例如：wangshenzhi/gemma2-9b-chinese-chat:latest）$}{$CP0=Please enter the Ollama model name (e.g., wangshenzhi/gemma2-9b-chinese-chat:latest).$}";
}

// 在 PotPlayer 登錄對話框中顯示的用戶輸入框文字，採用 $CP0=Model Name 風格以便取名
string GetUserText() {
    return "{$CP949=模型名稱 (當前: " + selected_model + ")$}{$CP950=模型名稱 (當前: " + selected_model + ")$}{$CP0=Model Name (Current: " + selected_model + ")$}";
}

// 無需密碼，保持空
string GetPasswordText() {
    return "";
}

// ----------------- 全局變量 -----------------
string selected_model = "wangshenzhi/gemma2-9b-chinese-chat:latest"; // 默認模型，可被 UI 覆蓋
string UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)";
string api_url = "http://127.0.0.1:11434/v1/chat/completions"; // 本地 Ollama 預設地址

// 支持語言表（簡化，PotPlayer 會使用這個列表填充下拉）
array<string> LangTable =
{
    "Auto", "en", "zh", "zh-CN", "zh-TW", "ja", "ko", "fr", "de", "es", "ru", "it", "pt"
};

// 返回來源語言列表（Auto 為自動檢測）
array<string> GetSrcLangs() {
    array<string> ret = LangTable;
    return ret;
}

// 返回目標語言列表
array<string> GetDstLangs() {
    array<string> ret = LangTable;
    return ret;
}

// ----------------- 登錄 / 登出 -----------------
// 接收 UI 的 User 為模型名稱，Pass 忽略（保持兼容）
string ServerLogin(string User, string Pass) {
    selected_model = User.Trim();
    if (selected_model.empty()) {
        HostPrintUTF8("{$CP949=模型名稱未輸入，請輸入有效的模型名稱（例如 wangshenzhi/gemma2-9b-chinese-chat:latest）。$}{$CP950=模型名稱未輸入，請輸入有效的模型名稱（例如 wangshenzhi/gemma2-9b-chinese-chat:latest）。$}{$CP0=Model name not entered. Please enter a valid model name (e.g., wangshenzhi/gemma2-9b-chinese-chat:latest).$}\n");
        selected_model = "wangshenzhi/gemma2-9b-chinese-chat:latest";
        return "fail";
    }
    // 保存到臨時存儲以便重啟後恢復
    HostSaveString("selected_model", selected_model);
    HostPrintUTF8("{$CP949=模型已設定: $}" + selected_model + "\n");
    return "200 ok";
}

void ServerLogout() {
    selected_model = "wangshenzhi/gemma2-9b-chinese-chat:latest";
    HostSaveString("selected_model", selected_model);
    HostPrintUTF8("{$CP949=已登出，模型已重置為默認值。$}{$CP950=已登出，模型已重置為默認值。$}{$CP0=Logged out and model reset to default.$}\n");
}

// ----------------- JSON 轉義工具 -----------------
// 將字符串轉為 JSON 字面量中的安全文本
string JsonEscape(const string &in input) {
    string output = input;
    output.replace("\\", "\\\\");
    output.replace("\"", "\\\"");
    output.replace("\n", "\\n");
    output.replace("\r", "\\r");
    output.replace("\t", "\\t");
    return output;
}

// ----------------- 翻譯函數 -----------------
// Text      : 要翻譯的文本（通常是 potplayer 實時字幕）
 // SrcLang  : 傳入時為來源語言代碼或 "Auto"（可被修改為實際傳回的編碼標識）
 // DstLang  : 目標語言代碼（必填）
 // 函數要求：僅返回翻譯文本（不帶任何額外說明）
string Translate(string Text, string &in SrcLang, string &in DstLang) {
    // 從臨時存儲讀取已保存的模型名稱（防止 potplayer 重啟後丟失）
    selected_model = HostLoadString("selected_model", selected_model);

    if (Text.empty()) return "";

    // 若目標語言未指定或為 Auto，則直接返回空（PotPlayer UI 應要求選擇目標語言）
    if (DstLang.empty() || DstLang == "Auto" || DstLang == "{$CP949=자동 감지$}{$CP950=自動檢測$}{$CP0=Auto Detect$}") {
        HostPrintUTF8("{$CP949=目標語言未指定，請在插件設定中選擇目標語言。$}{$CP950=目標語言未指定，請在插件設定中選擇目標語言。$}{$CP0=Target language not specified. Please choose a target language in plugin settings.$}\n");
        return "";
    }

    // 如果來源語言選為 Auto 或空，則不在提示中指定來源語言，讓模型自動判定
    string src_clause = "";
    if (!SrcLang.empty() && SrcLang != "Auto") {
        src_clause = " from " + SrcLang;
    }

    // 構建 prompt：簡短英文，要求模型僅輸出翻譯結果
    // 例： "Translate to zh: <text>\n\nOutput only the translated text."
    string short_prompt = "Translate" + src_clause + " to " + DstLang + ":\\n\\n" + Text + "\\n\\nOutput only the translated text.";

    // JSON 轉義
    string escapedUser = JsonEscape(short_prompt);

    // 使用簡單 system 指令來強化只輸出翻譯的要求
    string system_msg = "You are a translator. Output only the translated text without any extra explanation.";

    // 構建 Ollama /chat/completions 請求體
    string requestData = "{\"model\":\"" + selected_model + "\",\"messages\":[{\"role\":\"system\",\"content\":\"" + JsonEscape(system_msg) + "\"},{\"role\":\"user\",\"content\":\"" + escapedUser + "\"}],\"max_tokens\":2048}";

    // 發送 POST 請求到本地 Ollama
    string headers = "Content-Type: application/json";
    string response = HostUrlGetString(api_url, UserAgent, headers, requestData);

    if (response.empty()) {
        HostPrintUTF8("{$CP949=無法連接到本地 Ollama 服務，請確認服務在 http://127.0.0.1:11434 正常運行。$}{$CP950=無法連接到本地 Ollama 服務，請確認服務在 http://127.0.0.1:11434 正常運行。$}{$CP0=Failed to connect to local Ollama service. Ensure it is running at http://127.0.0.1:11434.$}\n");
        return "";
    }

    // 解析 JSON 響應，支援常見結構 choices[0].message.content 或 outputs[0].content
    JsonReader Reader;
    JsonValue Root;
    string translatedText = "";

    if (!Reader.parse(response, Root)) {
        // 若無法解析，直接嘗試截取簡單情況（防禦性）
        HostPrintUTF8("{$CP949=無法解析 Ollama 回應。回應內容: $}" + response + "\n");
        return "";
    }

    // 優先處理 OpenAI 風格的 choices->message->content
    if (Root.isObject() && Root["choices"].isArray() && Root["choices"][0]["message"]["content"].isString()) {
        translatedText = Root["choices"][0]["message"]["content"].asString();
    }
    // 再處理某些 Ollama 會使用 outputs 或 text 的情況
    else if (Root.isObject() && Root["outputs"].isArray() && Root["outputs"][0]["content"].isString()) {
        translatedText = Root["outputs"][0]["content"].asString();
    }
    // 再試 choices[0].text
    else if (Root.isObject() && Root["choices"].isArray() && Root["choices"][0]["text"].isString()) {
        translatedText = Root["choices"][0]["text"].asString();
    }
    // 最後嘗試直接取 root["text"]
    else if (Root.isObject() && Root["text"].isString()) {
        translatedText = Root["text"].asString();
    }

    // 若仍為空，返回空並輸出錯誤日誌
    if (translatedText.empty()) {
        HostPrintUTF8("{$CP949=未從 Ollama 回應中獲取到翻譯文本，請檢查模型輸出格式。$}{$CP950=未從 Ollama 回應中獲取到翻譯文本，請檢查模型輸出格式。$}{$CP0=No translated text found in Ollama response. Check model output format.$}\n");
        return "";
    }

    // 去掉首尾空白
    translatedText = translatedText.Trim();

    // 如果返回為多行，可以直接返回（PotPlayer 會顯示）
    // 對於從右至左語言（如 ar/he/fa）PotPlayer 可能需要處理，這裡不做特殊處理（如需可在此加上 Unicode RLE 前綴）
    SrcLang = "UTF8";
    DstLang = "UTF8";

    // 僅返回翻譯文本（插件要求）
    return translatedText;
}

// ----------------- 插件初始化 / 結束 -----------------
void OnInitialize() {
    HostPrintUTF8("{$CP949=Ollama 翻譯插件已加載。$}{$CP950=Ollama 翻譯插件已加載。$}{$CP0=Ollama translation plugin loaded.$}\n");
    // 嘗試從臨時存儲恢復模型名稱
    selected_model = HostLoadString("selected_model", selected_model);
    if (!selected_model.empty()) {
        HostPrintUTF8("{$CP949=已載入模型：$}" + selected_model + "\n");
    }
}

void OnFinalize() {
    HostPrintUTF8("{$CP949=Ollama 翻譯插件已卸載。$}{$CP950=Ollama 翻譯插件已卸載。$}{$CP0=Ollama translation plugin unloaded.$}\n");
}
