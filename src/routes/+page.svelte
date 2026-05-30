<script lang="ts">
  import DeepSeekStream from '$lib/DeepSeekStream.svelte';

  const PASSWORD = '0_51Dzhp';
  let unlocked = $state(sessionStorage.getItem('ds_unlocked') === '1');
  let passwordInput = $state('');
  let passError = $state(false);

  const demoPrompt =
    '请用 Python 写一个简易的 HTTP 代理服务器，要求：\n' +
    '1. 支持 GET/POST 请求转发\n' +
    '2. 支持并发处理多个请求（使用 asyncio）\n' +
    '3. 添加请求日志功能\n' +
    '4. 代码要有清晰的中文注释';

  const followUpPrompt =
    '请优化这段代码，增加以下功能：\n' +
    '1. 完善的错误处理和异常捕获\n' +
    '2. 请求/响应数据的日志记录到文件\n' +
    '3. 连接超时设置';

  function handleUnlock() {
    if (passwordInput === PASSWORD) {
      sessionStorage.setItem('ds_unlocked', '1');
      unlocked = true;
      passError = false;
    } else {
      passError = true;
    }
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter') handleUnlock();
  }
</script>

{#if unlocked}
  <div class="demo-page">
    <DeepSeekStream
      prompt={demoPrompt}
      followUpPrompt={followUpPrompt}
      followUpDelay={4000}
      apiKey={import.meta.env.VITE_DEEPSEEK_API_KEY || ''}
    />
  </div>
{:else}
  <div class="gate-page">
    <div class="gate-box">
      <h1>DeepSeekStream</h1>
      <p>请输入访问密码</p>
      <input
        type="password"
        class="gate-input"
        class:gate-input-error={passError}
        bind:value={passwordInput}
        onkeydown={handleKeydown}
        placeholder="密码"
        autofocus
      />
      {#if passError}
        <span class="gate-error">密码错误</span>
      {/if}
      <button class="gate-btn" onclick={handleUnlock}>继续访问</button>
    </div>
  </div>
{/if}

<style>
  .demo-page {
    width: 100vw;
    height: 100vh;
    background:
      radial-gradient(ellipse at 30% 20%, rgba(137, 180, 250, 0.04) 0%, transparent 50%),
      radial-gradient(ellipse at 70% 60%, rgba(166, 227, 161, 0.03) 0%, transparent 50%),
      #11111b;
    overflow: hidden;
  }

  .gate-page {
    width: 100vw;
    height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    background: #11111b;
  }

  .gate-box {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 1rem;
    padding: 2.5rem 2rem;
    background: #1e1e2e;
    border: 1px solid #313244;
    border-radius: 12px;
    min-width: 320px;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5);
  }

  .gate-box h1 {
    color: #cdd6f4;
    font-size: 1.25rem;
    font-weight: 600;
    margin: 0;
  }

  .gate-box p {
    color: #6c7086;
    font-size: 0.875rem;
    margin: 0;
  }

  .gate-input {
    width: 100%;
    padding: 0.625rem 0.875rem;
    background: #11111b;
    border: 1px solid #45475a;
    border-radius: 6px;
    color: #cdd6f4;
    font-size: 0.9375rem;
    outline: none;
    transition: border-color 0.15s;
    box-sizing: border-box;
  }

  .gate-input:focus {
    border-color: #89b4fa;
  }

  .gate-input-error {
    border-color: #f38ba8;
  }

  .gate-error {
    color: #f38ba8;
    font-size: 0.8125rem;
    margin-top: -0.5rem;
  }

  .gate-btn {
    width: 100%;
    padding: 0.625rem 0;
    background: #89b4fa;
    color: #1e1e2e;
    border: none;
    border-radius: 6px;
    font-size: 0.9375rem;
    font-weight: 500;
    cursor: pointer;
    transition: background 0.15s;
  }

  .gate-btn:hover {
    background: #b4d0fb;
  }
</style>
