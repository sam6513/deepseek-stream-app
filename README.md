# DeepSeekStream

> **For AI Agent** — 当你需要操作本仓库时，请遵循以下指南：
>
> ### 组件概览
> - `src/lib/DeepSeekStream.svelte` — 核心组件，可嵌入任意 Svelte 5/SvelteKit 项目
> - `src/routes/+page.svelte` — Demo 页面，展示组件的使用方式（带密码保护门禁）
> - 组件通过 `fetch` + `ReadableStream` 流式调用 DeepSeek API (`/v1/chat/completions`)，支持 SSE 解析
>
> ### 嵌入组件到新项目
> 1. 复制 `src/lib/DeepSeekStream.svelte` 到目标项目的 `$lib/` 目录
> 2. 安装依赖：`npm install marked highlight.js`
> 3. 在 Svelte 页面中导入并使用：
> ```svelte
> <DeepSeekStream
>   prompt="你的问题"
>   apiKey="sk-your-key"
>   model="deepseek-chat"
> />
> ```
>
> ### Props（全部可选）
> | Prop | 类型 | 默认值 | 说明 |
> |------|------|--------|------|
> | `prompt` | `string` | `''` | 用户消息，设值后默认自动发送 |
> | `apiKey` | `string` | `''` | DeepSeek API Key（必填才能调用） |
> | `apiUrl` | `string` | `https://api.deepseek.com` | 兼容 OpenAI 格式的 API 地址 |
> | `model` | `string` | `deepseek-v4-flash` | 模型名称 |
> | `systemPrompt` | `string` | `''` | 系统提示词（自动追加中文思考前缀） |
> | `autoStart` | `boolean` | `true` | 挂载后是否自动发送 prompt |
> | `followUpPrompt` | `string` | `''` | 首轮完成后自动发送的追加问题 |
> | `followUpDelay` | `number` | `3000` | 追加问题延迟（毫秒） |
>
> ### 暴露方法（bind:this）
> - `send(prompt: string): Promise<void>` — 发送新 prompt，自动携带对话历史
> - `reset(): void` — 清空对话和状态
>
> ### 会话持久化
> 对话历史（`messages[]`）自动保存到 `sessionStorage`，**刷新页面不会丢失对话**。关闭浏览器标签页后自动清除。调用 `reset()` 会同时清除持久化数据。
>
> **新 session 何时开始：**
> - 关闭浏览器标签页（`sessionStorage` 自动清除）
> - 调用 `reset()` 方法
> - 首次访问该域名页面
> - 存储数据损坏时自动回退到空白
> - 切换浏览器/设备（天然隔离）
>
> **使用时注意：**
> - **同域名多页面串号** — 同一域名下多个页面嵌入 DeepSeekStream 会共享 `ds_session_data` key，对话历史互相覆盖（当前版本未提供 `sessionKey` prop 做隔离）
> - **`reset()` 后不会自动开始** — 需要手动改变 `prompt` 或调用 `send()`，因为 `autoStart` 的 `$effect` 依赖于 `prompt` 变化
> - **流式输出中途刷新丢失未完成消息** — 已写入 `messages[]` 的 user 消息会持久化，但正在进行中的 assistant 流式内容会永久丢失（无法恢复断开的 HTTP 流）
> - **无痕/隐私模式静默失效** — 部分浏览器限制 `sessionStorage`，代码用 `try/catch` 兜底不会报错，但对话不会持久化
> - **长对话累积存储** — `sessionStorage` 上限约 5-10MB/域名，纯文本对话通常远低于此，但嵌入大段代码输出时需留意
> - **不跨标签页同步** — 多标签页各自独立的 `sessionStorage`，对话互不可见
>
> ### 构建与部署
> - `.env` 文件存放 `VITE_DEEPSEEK_API_KEY=sk-xxx`，Vite 构建时注入客户端
> - 生产部署：`./deploy.sh`（Docker 构建 + 运行，默认监听 `127.0.0.1:8102:3000`）
> - 本地开发：`npm install && npm run dev`
> - `.env` 已在 `.gitignore` 中，不会提交到仓库
>
> ### 密码保护
> `+page.svelte` 有密码门禁（硬编码 `0_51Dzhp`），解锁状态存 `sessionStorage`，关浏览器后需重新输入。如果不需要密码保护，直接去掉 `{#if unlocked}` 分支逻辑即可。

可嵌入网页的 LLM 响应展示面板。发送 prompt 到 DeepSeek API，流式渲染思考过程与最终回答。适用于技术博客、文档站点、产品演示等场景，让访客直接看到 AI 的推理和输出。

**不是对话机器人** — 这是一个单向的响应展示组件，用于呈现 LLM 对特定问题的回答，而非多轮闲聊。

## 效果

- 浮动面板（Terminal 风格），可拖拽、可调宽度、可最小化/最大化
- 流式逐字输出，实时展示思考过程（`reasoning_content`）
- 思考过程默认折叠，实时计时，完成后显示 "已深度思考 Xs"
- 完整 Markdown 渲染 + 代码语法高亮（highlight.js）
- 支持连续多轮问答（如 "写代码 → 优化这段代码"）

## 快速开始

### 嵌入已有 SvelteKit 项目

```bash
npm install marked highlight.js
```

复制 `src/lib/DeepSeekStream.svelte` 到你的项目中，然后：

```svelte
<script>
  import DeepSeekStream from '$lib/DeepSeekStream.svelte';
</script>

<DeepSeekStream
  prompt="请用 Python 写一个快速排序算法"
  apiKey="sk-your-deepseek-key"
  model="deepseek-chat"
/>
```

### 独立部署（Docker）

```bash
docker build -t deepseek-stream-app .
docker run -d --name deepseek-stream --restart always -p 3000:3000 deepseek-stream-app
```

## Props

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `prompt` | `string` | `''` | 用户消息，设置后 `autoStart=true` 时自动发送 |
| `apiKey` | `string` | (demo key) | DeepSeek API key |
| `apiUrl` | `string` | `https://api.deepseek.com` | API 地址，兼容 OpenAI 格式 |
| `model` | `string` | `deepseek-v4-flash` | 模型名称 |
| `systemPrompt` | `string` | `''` | 系统提示词（会自动追加中文思考前缀） |
| `autoStart` | `boolean` | `true` | 挂载后是否自动发送 prompt |
| `followUpPrompt` | `string` | `''` | 第一轮完成后自动发送的追加问题 |
| `followUpDelay` | `number` | `3000` | 追加问题的延迟（毫秒） |

## 暴露方法

通过 `bind:this` 获取组件实例后调用：

```svelte
<script>
  import DeepSeekStream from '$lib/DeepSeekStream.svelte';
  let ds;

  function askAgain() {
    ds.send('请换一种方式实现');
  }
</script>

<DeepSeekStream bind:this={ds} prompt="..." autoStart={false} />
<button onclick={askAgain}>追问</button>
```

### `send(prompt: string): Promise<void>`

发送新的 prompt。会自动携带之前的对话历史作为上下文。

### `reset(): void`

清空所有状态和对话历史。

## 会话持久化

对话历史（`messages[]`）自动保存到 `sessionStorage`，**刷新页面不会丢失对话**。关闭浏览器标签页后自动清除。调用 `reset()` 会同时清除持久化数据。

### 何时开始新 session

| 触发方式 | 行为 |
|----------|------|
| **关闭标签页** | `sessionStorage` 浏览器自动清除，新标签页 = 全新对话 |
| **调用 `reset()`** | `ds.reset()` → 清内存 + 删持久化 |
| **首次访问** | 无对应存储 key → 空白起始 |
| **数据损坏** | JSON 解析失败或校验不通过 → 静默回退到空白 |
| **切换浏览器/设备** | `sessionStorage` 按浏览器+域名隔离，天然不互通 |

### 注意事项

- **同域名多页面串号** — 同一域名下多个页面嵌入 DeepSeekStream 会共享 `ds_session_data` key，对话历史互相覆盖（当前版本未提供 `sessionKey` prop 做隔离）
- **`reset()` 后不会自动开始** — 需要手动改变 `prompt` 或调用 `send()`，因为 `autoStart` 的 `$effect` 依赖于 `prompt` 变化
- **流式输出中途刷新丢失未完成消息** — 已写入 `messages[]` 的 user 消息会持久化，但正在进行中的 assistant 流式内容会永久丢失（无法恢复断开的 HTTP 流）
- **无痕/隐私模式静默失效** — 部分浏览器限制 `sessionStorage`，代码用 `try/catch` 兜底不会报错，但对话不会持久化
- **长对话累积存储** — `sessionStorage` 上限约 5-10MB/域名，纯文本对话通常远低于此，但嵌入大段代码输出时需留意
- **不跨标签页同步** — 多标签页各自独立的 `sessionStorage`，对话互不可见

## 依赖

- `marked` (^9.x) — Markdown 解析
- `highlight.js` (^11.x) — 代码语法高亮
- Svelte 5 + SvelteKit

不依赖 Tailwind、Open WebUI 内部模块或其他第三方库。

## 技术细节

- **流式解析**：`fetch` + `ReadableStream` 直接调用 DeepSeek `/v1/chat/completions`，手动解析 SSE
- **思考过程**：从 `choices[0].delta.reasoning_content` 提取，非标准字段，需模型支持
- **自动滚动**：`$effect` 监听内容变化 + `requestAnimationFrame` 节流，检测用户手动上滚时暂停
- **API 兼容**：使用 OpenAI 兼容的 chat completions 格式，可切换其他 API 地址
