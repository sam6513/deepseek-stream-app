# DeepSeekStream

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
