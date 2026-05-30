<script lang="ts">
  import { marked } from 'marked';
  import hljs from 'highlight.js';

  interface Props {
    prompt?: string;
    apiKey?: string;
    apiUrl?: string;
    model?: string;
    systemPrompt?: string;
    autoStart?: boolean;
    followUpPrompt?: string;
    followUpDelay?: number;
  }

  let {
    prompt = '',
    apiKey = '',
    apiUrl = 'https://api.deepseek.com',
    model = 'deepseek-v4-flash',
    systemPrompt = '',
    autoStart = true,
    followUpPrompt = '',
    followUpDelay = 3000,
  }: Props = $props();

  interface Message {
    id: string;
    role: 'user' | 'assistant';
    content: string;
    thinking?: string;
    thinkingDuration?: number;
  }

  let messages = $state<Message[]>([]);
  let currentThinking = $state('');
  let currentContent = $state('');
  let currentThinkingDone = $state(false);
  let currentThinkingDuration = $state(0);
  let liveDuration = $state(0);
  let done = $state(false);
  let streaming = $state(false);
  let error = $state('');
  let visible = $state(true);
  let minimized = $state(false);
  let maximized = $state(false);
  let copied = $state(false);

  // Saved position/size for restore from maximize
  let savedX = 720;
  let savedY = 0;
  let savedWidth = 720;

  let thinkingStartTime = 0;
  let thinkingEndTime = 0;
  let abortController: AbortController | null = null;
  let liveTimer: ReturnType<typeof setInterval> | null = null;
  let streamEl: HTMLDivElement | null = null;
  let autoScroll = true;
  let scrollRAF: number | null = null;
  let sendCount = 0;

  // ── Session persistence (sessionStorage) ──────────────────
  const SESSION_STORE = 'ds_session_data';

  function loadSession() {
    try {
      const raw = sessionStorage.getItem(SESSION_STORE);
      if (!raw) return;
      const data = JSON.parse(raw);
      if (Array.isArray(data.messages) && data.messages.length > 0) {
        messages = data.messages;
        sendCount = typeof data.sendCount === 'number' ? data.sendCount : 0;
        done = true; // restored messages are already finalized
      }
    } catch {
      // sessionStorage unavailable or corrupted — silent fallback
    }
  }

  function saveSession() {
    try {
      sessionStorage.setItem(SESSION_STORE, JSON.stringify({
        messages,
        sendCount,
      }));
    } catch {
      // sessionStorage full or unavailable — silent fallback
    }
  }

  function clearSession() {
    try {
      sessionStorage.removeItem(SESSION_STORE);
    } catch {
      // silent fallback
    }
  }

  // Restore on mount (before $effect auto-start runs)
  loadSession();

  // Panel drag state
  let panelX = $state(0);
  let panelY = $state(0);
  let panelWidth = $state(720);
  let panelInitialized = false;
  let dragging = false;
  let dragStartX = 0;
  let dragStartY = 0;
  let panelStartX = 0;
  let panelStartY = 0;

  // Resize state
  let resizing = false;
  let resizeStartX = 0;
  let widthStart = 0;

  function initPanelPosition() {
    if (panelInitialized) return;
    panelInitialized = true;
    panelX = Math.max(20, (window.innerWidth - panelWidth) / 2);
    panelY = Math.max(20, window.innerHeight * 0.05);
  }
  initPanelPosition();

  function startResize(e: MouseEvent) {
    e.preventDefault();
    e.stopPropagation();
    resizing = true;
    resizeStartX = e.clientX;
    widthStart = panelWidth;
    window.addEventListener('mousemove', onResize);
    window.addEventListener('mouseup', stopResize);
  }

  function onResize(e: MouseEvent) {
    if (!resizing) return;
    panelWidth = Math.max(420, Math.min(window.innerWidth - panelX - 20, widthStart + (e.clientX - resizeStartX)));
  }

  function stopResize() {
    resizing = false;
    window.removeEventListener('mousemove', onResize);
    window.removeEventListener('mouseup', stopResize);
  }

  function toggleMinimize() {
    if (maximized) return; // can't minimize when maximized
    minimized = !minimized;
  }

  function toggleMaximize() {
    if (minimized) {
      minimized = false;
      return;
    }
    if (maximized) {
      // Restore
      panelX = savedX;
      panelY = savedY;
      panelWidth = savedWidth;
      maximized = false;
    } else {
      // Save and maximize
      savedX = panelX;
      savedY = panelY;
      savedWidth = panelWidth;
      panelX = 0;
      panelY = 0;
      panelWidth = window.innerWidth;
      maximized = true;
    }
  }

  marked.setOptions({
    breaks: true,
    gfm: true,
  });

  marked.use({
    renderer: {
      code(text: string, lang: string | undefined) {
        const validLang = lang && hljs.getLanguage(lang) ? lang : undefined;
        let highlighted: string;
        if (validLang) {
          try {
            highlighted = hljs.highlight(text, { language: validLang }).value;
          } catch {
            highlighted = hljs.highlightAuto(text).value;
          }
        } else {
          highlighted = hljs.highlightAuto(text).value;
        }
        const langLabel = validLang || '';
        return `<pre><code class="hljs language-${langLabel}">${highlighted}</code></pre>`;
      },
    } as any,
  });

  function startLiveTimer() {
    if (liveTimer) return;
    liveTimer = setInterval(() => {
      if (thinkingStartTime && !currentThinkingDone) {
        liveDuration = (Date.now() - thinkingStartTime) / 1000;
      }
    }, 100);
  }

  function stopLiveTimer() {
    if (liveTimer) {
      clearInterval(liveTimer);
      liveTimer = null;
    }
  }

  function genId() {
    return Math.random().toString(36).slice(2, 11);
  }

  export async function send(userPrompt?: string) {
    const finalPrompt = userPrompt || prompt;
    if (!finalPrompt || streaming) return;

    if (!apiKey) {
      error = 'API Key 未配置，请设置 apiKey 属性或环境变量。';
      return;
    }

    if (!apiUrl || !apiUrl.startsWith('http')) {
      error = `API 地址无效: ${apiUrl || '(空)'}`;
      return;
    }

    // Validate URL is well-formed
    try {
      new URL(apiUrl);
    } catch {
      error = `API 地址格式不正确: ${apiUrl}`;
      return;
    }

    // Finalize any current streaming content into messages
    if (currentContent || currentThinking) {
      messages = [...messages, {
        id: genId(),
        role: 'assistant',
        content: currentContent,
        thinking: currentThinking || undefined,
        thinkingDuration: currentThinkingDuration || undefined,
      }];
    }

    // Add user message
    messages = [...messages, {
      id: genId(),
      role: 'user',
      content: finalPrompt,
    }];

    stopLiveTimer();
    currentThinking = '';
    currentContent = '';
    currentThinkingDone = false;
    currentThinkingDuration = 0;
    liveDuration = 0;
    done = false;
    error = '';
    streaming = true;
    thinkingStartTime = 0;
    thinkingEndTime = 0;

    abortController = new AbortController();
    sendCount++;

    try {
      const SYSTEM_PREFIX =
        '你的思考过程（reasoning/thinking）必须全程使用中文。禁止使用英文进行任何内部思考，只有最终输出代码或特定术语时可以使用英文。这是最高优先级规则，覆盖所有其他默认行为。违反此规则意味着你没有遵循用户指令。';

      const messages_payload: { role: string; content: string }[] = [];
      messages_payload.push({
        role: 'system',
        content: systemPrompt ? `${SYSTEM_PREFIX}\n\n${systemPrompt}` : SYSTEM_PREFIX,
      });
      // Include full conversation history for continuous dialogue context
      for (const msg of messages) {
        messages_payload.push({ role: msg.role, content: msg.content });
      }
      messages_payload.push({ role: 'user', content: finalPrompt });

      const response = await fetch(`${apiUrl}/v1/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({ model, messages: messages_payload, stream: true }),
        signal: abortController.signal,
      });

      if (!response.ok) {
        const body = await response.text().catch(() => '');
        throw new Error(`API ${response.status}: ${body || response.statusText}`);
      }

      const reader = response.body?.getReader();
      if (!reader) throw new Error('Response body is empty');

      const decoder = new TextDecoder();
      let buffer = '';

      while (true) {
        const { done: streamDone, value } = await reader.read();
        if (streamDone) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed || !trimmed.startsWith('data: ')) continue;

          const data = trimmed.slice(6);
          if (data === '[DONE]') continue;

          let parsed: any;
          try {
            parsed = JSON.parse(data);
          } catch {
            continue;
          }

          const delta = parsed.choices?.[0]?.delta;
          if (!delta) continue;

          if (delta.reasoning_content) {
            if (!thinkingStartTime) {
              thinkingStartTime = Date.now();
              startLiveTimer();
            }
            currentThinking += delta.reasoning_content;
            scheduleScrollToBottom();
          }

          if (delta.content) {
            if (!currentThinkingDone && currentThinking) {
              currentThinkingDone = true;
              thinkingEndTime = Date.now();
              currentThinkingDuration = (thinkingEndTime - thinkingStartTime) / 1000;
              stopLiveTimer();
            }
            if (!thinkingStartTime) thinkingStartTime = Date.now();
            currentContent += delta.content;
            scheduleScrollToBottom();
          }
        }
      }
    } catch (e: any) {
      if (e.name !== 'AbortError') {
        error = e.message || 'Unknown error';
      }
    } finally {
      done = true;
      streaming = false;
      stopLiveTimer();
      if (!currentThinkingDone && currentThinking) {
        currentThinkingDone = true;
        thinkingEndTime = Date.now();
        currentThinkingDuration = (thinkingEndTime - thinkingStartTime) / 1000;
      }
      // Finalize assistant message
      if (currentContent || currentThinking) {
        messages = [...messages, {
          id: genId(),
          role: 'assistant',
          content: currentContent,
          thinking: currentThinking || undefined,
          thinkingDuration: currentThinkingDuration || undefined,
        }];
        currentThinking = '';
        currentContent = '';
        currentThinkingDone = false;
        currentThinkingDuration = 0;
      }
      // Auto-send follow-up if configured
      if (followUpPrompt && sendCount === 1 && !error) {
        setTimeout(() => send(followUpPrompt), followUpDelay);
      }
    }
  }

  export function reset() {
    stopLiveTimer();
    abortController?.abort();
    messages = [];
    currentThinking = '';
    currentContent = '';
    currentThinkingDone = false;
    currentThinkingDuration = 0;
    liveDuration = 0;
    done = false;
    streaming = false;
    error = '';
    sendCount = 0;
    clearSession();
  }

  function formatDuration(seconds: number): string {
    if (!seconds || seconds < 0) return '0s';
    if (seconds < 1) return `${Math.round(seconds * 1000)}ms`;
    if (seconds < 60) return `${seconds.toFixed(1)}s`;
    const m = Math.floor(seconds / 60);
    const s = Math.round(seconds % 60);
    return `${m}m ${s}s`;
  }

  function scrollToBottom() {
    if (!streamEl || !autoScroll) return;
    streamEl.scrollTop = streamEl.scrollHeight;
    requestAnimationFrame(() => {
      if (!streamEl || !autoScroll) return;
      streamEl.scrollTop = streamEl.scrollHeight;
      requestAnimationFrame(() => {
        if (!streamEl || !autoScroll) return;
        streamEl.scrollTop = streamEl.scrollHeight;
      });
    });
  }

  function scheduleScrollToBottom() {
    if (!scrollRAF) {
      scrollRAF = requestAnimationFrame(() => {
        scrollRAF = null;
        scrollToBottom();
      });
    }
  }

  function onScroll() {
    if (!streamEl) return;
    autoScroll =
      streamEl.scrollHeight - streamEl.scrollTop <= streamEl.clientHeight + 5;
  }

  function startDrag(e: MouseEvent) {
    dragging = true;
    dragStartX = e.clientX;
    dragStartY = e.clientY;
    panelStartX = panelX;
    panelStartY = panelY;
    window.addEventListener('mousemove', onDrag);
    window.addEventListener('mouseup', stopDrag);
  }

  function onDrag(e: MouseEvent) {
    if (!dragging) return;
    panelX = panelStartX + (e.clientX - dragStartX);
    panelY = panelStartY + (e.clientY - dragStartY);
  }

  function stopDrag() {
    dragging = false;
    window.removeEventListener('mousemove', onDrag);
    window.removeEventListener('mouseup', stopDrag);
  }

  async function copyAll() {
    const parts: string[] = [];
    for (const m of messages) {
      if (m.role === 'user') {
        parts.push(`▸ ${m.content}`);
      } else {
        parts.push(m.content);
      }
    }
    if (currentContent) parts.push(currentContent);
    const text = parts.join('\n\n---\n\n');
    try {
      await navigator.clipboard.writeText(text);
      copied = true;
      setTimeout(() => (copied = false), 2000);
    } catch {
      // fallback
      const ta = document.createElement('textarea');
      ta.value = text;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
      copied = true;
      setTimeout(() => (copied = false), 2000);
    }
  }

  $effect(() => {
    if (autoStart && prompt && !done && !streaming && messages.length === 0) {
      send();
    }
  });

  // Persist conversation to sessionStorage whenever messages or sendCount change
  $effect(() => {
    void messages.length;
    void sendCount;
    if (messages.length > 0) {
      saveSession();
    } else {
      clearSession();
    }
  });

  $effect(() => {
    void messages;
    void currentThinking;
    void currentContent;
    scrollToBottom();
  });
</script>

{#if visible}
  <div
    class="ds-panel"
    class:ds-maximized={maximized}
    class:ds-minimized={minimized}
    style="left: {panelX}px; top: {panelY}px; width: {panelWidth}px"
    role="dialog"
    aria-label="Agent响应面板"
  >
    <!-- Title bar -->
    <div
      class="ds-titlebar"
      role="toolbar"
      aria-label="面板工具栏"
    >
      <div class="ds-dots">
        <span class="ds-dot ds-dot-red" onclick={() => (visible = false)} title="关闭面板"></span>
        <span class="ds-dot ds-dot-yellow" onclick={toggleMinimize} title={minimized ? '展开面板' : '最小化面板'}></span>
        <span class="ds-dot ds-dot-green" onclick={toggleMaximize} title={maximized ? '还原面板' : '最大化面板'}></span>
      </div>
      <span class="ds-title-text" onmousedown={startDrag}>Agent响应面板</span>
      <div class="ds-title-actions">
        <button class="ds-title-btn" onclick={copyAll} title="复制全部回复">
          {#if copied}
            <svg viewBox="0 0 20 20" fill="currentColor" width="14" height="14">
              <path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 01.143 1.052l-8 10.5a.75.75 0 01-1.127.075l-4.5-4.5a.75.75 0 011.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 011.05-.143z" clip-rule="evenodd" />
            </svg>
          {:else}
            <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" width="14" height="14">
              <rect x="5.5" y="4.5" width="10" height="12" rx="1.5" />
              <rect x="3" y="1.5" width="10" height="12" rx="1.5" fill="#181825" stroke="currentColor" />
            </svg>
          {/if}
        </button>
        <button class="ds-title-btn ds-title-btn-close" onclick={() => (visible = false)} title="关闭面板">
          <svg viewBox="0 0 20 20" fill="currentColor" width="14" height="14">
            <path d="M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z" />
          </svg>
        </button>
      </div>
    </div>

    <!-- Content area -->
    {#if !minimized}
    <div class="ds-content" bind:this={streamEl} onscroll={onScroll}>
      {#if error}
        <div class="ds-error" role="alert">
          <svg class="ds-error-icon" viewBox="0 0 20 20" fill="currentColor" width="16" height="16">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z" clip-rule="evenodd" />
          </svg>
          <div>
            <div class="ds-error-title">Request failed</div>
            <div class="ds-error-body">{error}</div>
          </div>
        </div>
      {/if}

      {#each messages as msg}
        {#if msg.role === 'user'}
          <div class="ds-user-msg">
            <span class="ds-prompt-icon">
              <svg viewBox="0 0 20 20" fill="currentColor" width="14" height="14">
                <path d="M10 2a1.5 1.5 0 00-1.5 1.5v1.793l-1.22-1.22a.75.75 0 10-1.06 1.06L7.793 6.5H6.5a.75.75 0 000 1.5h1.793l.72.72-.72.72H6.5a.75.75 0 000 1.5h1.793l-1.573 1.573a.75.75 0 101.06 1.06L8.5 12.707v1.793a1.5 1.5 0 003 0v-1.793l1.22 1.22a.75.75 0 101.06-1.06l-1.573-1.573h1.793a.75.75 0 000-1.5h-1.793l-.72-.72.72-.72h1.793a.75.75 0 000-1.5h-1.793l1.573-1.573a.75.75 0 10-1.06-1.06L11.5 6.207V4.5A1.5 1.5 0 0010 2z" />
              </svg>
            </span>
            <div class="ds-user-text">{msg.content}</div>
          </div>
        {:else}
          <div class="ds-assistant-msg">
            {#if msg.thinking}
              <details class="ds-thinking">
                <summary class="ds-thinking-summary">
                  <span class="ds-thinking-indicator">
                    <svg class="ds-check" viewBox="0 0 20 20" fill="currentColor" width="14" height="14">
                      <path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 01.143 1.052l-8 10.5a.75.75 0 01-1.127.075l-4.5-4.5a.75.75 0 011.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 011.05-.143z" clip-rule="evenodd" />
                    </svg>
                    已深度思考 {formatDuration(msg.thinkingDuration || 0)}
                  </span>
                </summary>
                <div class="ds-thinking-content">{msg.thinking}</div>
              </details>
            {/if}
            <div class="ds-body">
              {@html marked.parse(msg.content)}
            </div>
          </div>
        {/if}
      {/each}

      {#if currentThinking || currentContent}
        <div class="ds-assistant-msg ds-assistant-msg-live">
          {#if currentThinking}
            <details class="ds-thinking" open>
              <summary class="ds-thinking-summary">
                <span class="ds-thinking-indicator">
                  {#if !currentThinkingDone}
                    <span class="ds-spinner"></span>
                    思考中... {liveDuration.toFixed(0)}s
                  {:else}
                    <svg class="ds-check" viewBox="0 0 20 20" fill="currentColor" width="14" height="14">
                      <path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 01.143 1.052l-8 10.5a.75.75 0 01-1.127.075l-4.5-4.5a.75.75 0 011.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 011.05-.143z" clip-rule="evenodd" />
                    </svg>
                    已深度思考 {formatDuration(currentThinkingDuration)}
                  {/if}
                </span>
              </summary>
              <div class="ds-thinking-content">{currentThinking}</div>
            </details>
          {/if}
          {#if currentContent}
            <div class="ds-body">
              {@html marked.parse(currentContent)}
            </div>
          {/if}
        </div>
      {/if}

      {#if streaming && !currentContent && !currentThinking}
        <div class="ds-loading">
          <span class="ds-spinner"></span>
          连接中...
        </div>
      {/if}

      {#if !streaming && !error && messages.length === 0 && !currentContent && !currentThinking}
        <div class="ds-empty">准备就绪，等待发送消息。</div>
      {/if}
    </div>
    <div class="ds-resize-handle" onmousedown={startResize}></div>
    {/if}
  </div>
{/if}

<style>
  /* ===== Panel shell ===== */
  .ds-panel {
    position: fixed;
    max-height: 85vh;
    min-width: 420px;
    background: #1e1e2e;
    border: 1px solid #313244;
    border-radius: 10px;
    box-shadow:
      0 8px 32px rgba(0, 0, 0, 0.55),
      0 0 0 1px rgba(255, 255, 255, 0.03) inset;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    z-index: 9999;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
  }

  /* ===== Panel states ===== */
  .ds-maximized {
    border-radius: 0;
    max-height: 100vh;
  }
  .ds-minimized .ds-titlebar {
    border-bottom: none;
    border-radius: 10px;
  }

  /* ===== Resize handle ===== */
  .ds-resize-handle {
    position: absolute;
    right: 0;
    top: 0;
    bottom: 0;
    width: 6px;
    cursor: ew-resize;
    z-index: 10;
  }
  .ds-resize-handle:hover,
  .ds-resize-handle:active {
    background: rgba(137, 180, 250, 0.25);
  }

  /* ===== Title bar ===== */
  .ds-titlebar {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.625rem 0.875rem;
    background: #181825;
    border-bottom: 1px solid #313244;
    flex-shrink: 0;
  }

  .ds-dots {
    display: flex;
    gap: 6px;
    flex-shrink: 0;
  }
  .ds-dot {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    transition: opacity 0.15s;
  }
  .ds-dot-red {
    background: #f38ba8;
    cursor: pointer;
  }
  .ds-dot-red:hover { opacity: 0.7; }
  .ds-dot-yellow {
    background: #fab387;
  }
  .ds-dot-green {
    background: #a6e3a1;
  }

  .ds-title-text {
    flex: 1;
    text-align: center;
    font-size: 0.8125rem;
    font-weight: 500;
    color: #a6adc8;
    letter-spacing: 0.02em;
    cursor: grab;
    user-select: none;
  }
  .ds-title-text:active {
    cursor: grabbing;
  }

  .ds-title-actions {
    display: flex;
    gap: 2px;
    flex-shrink: 0;
  }
  .ds-title-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    border: none;
    background: transparent;
    color: #6c7086;
    border-radius: 6px;
    cursor: pointer;
    transition: all 0.15s;
  }
  .ds-title-btn:hover {
    background: #313244;
    color: #cdd6f4;
  }
  .ds-title-btn-close:hover {
    background: #f38ba8;
    color: #1e1e2e;
  }

  /* ===== Content area ===== */
  .ds-content {
    flex: 1;
    overflow-y: auto;
    padding: 0.75rem 1rem 1rem;
    font-size: 14px;
    line-height: 1.65;
    color: #cdd6f4;
    scrollbar-width: thin;
    scrollbar-color: #45475a transparent;
    min-height: 0;
  }

  /* ===== Error ===== */
  .ds-error {
    display: flex;
    gap: 0.5rem;
    padding: 0.75rem 0.875rem;
    margin-bottom: 0.75rem;
    background: rgba(243, 139, 168, 0.1);
    border: 1px solid rgba(243, 139, 168, 0.35);
    border-radius: 0.5rem;
    color: #f38ba8;
    font-size: 0.8125rem;
  }
  .ds-error-icon { flex-shrink: 0; margin-top: 0.125rem; }
  .ds-error-title { font-weight: 600; }
  .ds-error-body { margin-top: 0.125rem; word-break: break-word; }

  /* ===== User message ===== */
  .ds-user-msg {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 1rem;
    padding: 0.625rem 0.75rem;
    background: rgba(137, 180, 250, 0.06);
    border: 1px solid rgba(137, 180, 250, 0.15);
    border-radius: 0.5rem;
  }
  .ds-prompt-icon {
    flex-shrink: 0;
    color: #89b4fa;
    margin-top: 1px;
  }
  .ds-user-text {
    color: #cdd6f4;
    white-space: pre-wrap;
    word-break: break-word;
    font-size: 0.875rem;
  }

  /* ===== Assistant message ===== */
  .ds-assistant-msg {
    background: #181825;
    border: 1px solid #313244;
    border-radius: 0.625rem;
    overflow: hidden;
    margin-bottom: 0.75rem;
  }
  .ds-assistant-msg-live {
    border-color: rgba(166, 227, 161, 0.3);
  }

  /* ===== Thinking ===== */
  .ds-thinking {
    border-bottom: 1px solid #313244;
  }
  .ds-thinking[open] {
    border-bottom: 1px solid #45475a;
  }
  .ds-thinking-summary {
    padding: 0.5rem 0.75rem;
    cursor: pointer;
    user-select: none;
    font-size: 0.75rem;
    color: #a6adc8;
    list-style: none;
    display: flex;
    align-items: center;
    background: #11111b;
    transition: background 0.15s;
  }
  .ds-thinking-summary::-webkit-details-marker { display: none; }
  .ds-thinking-summary:hover { background: #181825; }
  .ds-thinking-indicator {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
  }
  .ds-thinking-content {
    padding: 0.625rem 0.75rem;
    font-size: 0.75rem;
    color: #6c7086;
    font-family: 'JetBrains Mono', 'Fira Code', 'Cascadia Code', 'SF Mono', Consolas, monospace;
    white-space: pre-wrap;
    word-break: break-word;
    max-height: 14rem;
    overflow-y: auto;
  }

  /* ===== Response body ===== */
  .ds-body {
    padding: 0.75rem 0.875rem;
    color: #cdd6f4;
  }
  .ds-body :global(p) { margin: 0.4rem 0; }
  .ds-body :global(h1) { font-size: 1.35rem; font-weight: 700; margin: 1rem 0 0.5rem; color: #f5e0dc; }
  .ds-body :global(h2) { font-size: 1.15rem; font-weight: 600; margin: 0.875rem 0 0.5rem; color: #f2cdcd; }
  .ds-body :global(h3) { font-size: 1rem; font-weight: 600; margin: 0.75rem 0 0.375rem; color: #cdd6f4; }
  .ds-body :global(ul), .ds-body :global(ol) { padding-left: 1.5rem; margin: 0.4rem 0; }
  .ds-body :global(li) { margin: 0.2rem 0; }
  .ds-body :global(a) { color: #89b4fa; text-decoration: underline; }
  .ds-body :global(blockquote) { border-left: 3px solid #45475a; padding-left: 0.75rem; margin: 0.5rem 0; color: #a6adc8; }
  .ds-body :global(table) { width: 100%; border-collapse: collapse; margin: 0.5rem 0; font-size: 0.8125rem; }
  .ds-body :global(th) { background: #1e1e2e; font-weight: 600; text-align: left; padding: 0.375rem 0.625rem; border: 1px solid #45475a; }
  .ds-body :global(td) { padding: 0.375rem 0.625rem; border: 1px solid #45475a; }
  .ds-body :global(tr:nth-child(even)) { background: rgba(255,255,255,0.02); }
  .ds-body :global(hr) { border: none; border-top: 1px solid #45475a; margin: 0.75rem 0; }
  .ds-body :global(strong) { font-weight: 600; color: #f5e0dc; }
  .ds-body :global(code) {
    font-family: 'JetBrains Mono', 'Fira Code', 'Cascadia Code', 'SF Mono', Consolas, monospace;
    font-size: 0.85em; background: #313244; padding: 0.15em 0.35em; border-radius: 0.25rem; color: #fab387;
  }
  .ds-body :global(pre) { margin: 0.5rem 0; border-radius: 0.5rem; overflow-x: auto; border: 1px solid #45475a; }
  .ds-body :global(pre code) { display: block; padding: 0.75rem; background: #11111b; font-size: 0.8125rem; line-height: 1.55; overflow-x: auto; color: #cdd6f4; }
  .ds-body :global(.hljs) { background: #11111b; color: #cdd6f4; }
  .ds-body :global(.hljs-keyword) { color: #cba6f7; }
  .ds-body :global(.hljs-string)  { color: #a6e3a1; }
  .ds-body :global(.hljs-number)  { color: #fab387; }
  .ds-body :global(.hljs-comment) { color: #6c7086; font-style: italic; }
  .ds-body :global(.hljs-function) { color: #89b4fa; }
  .ds-body :global(.hljs-title)   { color: #89b4fa; }
  .ds-body :global(.hljs-params)  { color: #f2cdcd; }
  .ds-body :global(.hljs-built_in) { color: #f2cdcd; }
  .ds-body :global(.hljs-type)    { color: #fab387; }
  .ds-body :global(.hljs-literal) { color: #cba6f7; }
  .ds-body :global(.hljs-attr)    { color: #89b4fa; }
  .ds-body :global(.hljs-selector-class) { color: #fab387; }
  .ds-body :global(.hljs-selector-tag)   { color: #cba6f7; }
  .ds-body :global(.hljs-variable) { color: #f38ba8; }
  .ds-body :global(.hljs-meta)    { color: #fab387; }
  .ds-body :global(.hljs-regexp)  { color: #f38ba8; }
  .ds-body :global(.hljs-deletion) { color: #f38ba8; }
  .ds-body :global(.hljs-addition) { color: #a6e3a1; }
  .ds-body :global(.hljs-emphasis) { font-style: italic; }
  .ds-body :global(.hljs-strong)   { font-weight: 700; }

  /* ===== Spinner ===== */
  .ds-spinner {
    display: inline-block;
    width: 12px;
    height: 12px;
    border: 2px solid #45475a;
    border-top-color: #a6adc8;
    border-radius: 50%;
    animation: ds-spin 0.6s linear infinite;
    flex-shrink: 0;
  }
  @keyframes ds-spin { to { transform: rotate(360deg); } }

  .ds-check { color: #a6e3a1; flex-shrink: 0; }

  .ds-loading {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.75rem;
    color: #a6adc8;
    font-size: 0.8125rem;
  }

  .ds-empty {
    text-align: center;
    padding: 2rem;
    color: #6c7086;
    font-size: 0.8125rem;
  }
</style>
