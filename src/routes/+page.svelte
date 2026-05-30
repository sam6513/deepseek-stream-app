<script lang="ts">
  import DeepSeekStream from '$lib/DeepSeekStream.svelte';

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
</script>

<div class="demo-page">
  <DeepSeekStream
    prompt={demoPrompt}
    followUpPrompt={followUpPrompt}
    followUpDelay={4000}
    apiKey={import.meta.env.VITE_DEEPSEEK_API_KEY || ''}
  />
</div>

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
</style>
