/** Feedback for the source's manual QR confirmation; never reads or logs login request bodies. */
export class CatNodeConfigurationScript {
  static build(): string {
    return `(() => {
      if (location.protocol !== 'http:' || location.hostname !== '127.0.0.1') return;
      if (location.pathname !== '/website' && location.pathname !== '/website/') return;
      if (window.__catLoginFeedback) return;
      window.__catLoginFeedback = true;
      const fetchOriginal = window.fetch.bind(window);
      let requests = 0;
      let pending = 0;
      const message = (text) => { if (typeof window.setMessage === 'function') window.setMessage(text, true); };
      const log = (phase, action, status) => console.info('[CatConfigLogin] phase=' + phase + ' action=' + action + ' status=' + status);
      window.fetch = async (input, options) => {
        let target;
        try { target = new URL(typeof input === 'string' || input instanceof URL ? input : input.url, location.href); }
        catch (_) { return fetchOriginal(input, options); }
        const method = String(options && options.method || input && input.method || 'GET').toUpperCase();
        const match = target.pathname.match(/^\\/website\\/api\\/(?:bili\\/)?login\\/(start|poll|cancel)$/);
        if (target.origin !== location.origin || method !== 'POST' || !match) return fetchOriginal(input, options);
        const action = match[1];
        requests++;
        const button = action === 'poll' ? document.getElementById('confirmLoginBtn') : null;
        if (button) { pending++; button.disabled = true; button.textContent = '正在确认…'; }
        log('request', action, 'pending');
        const abort = new AbortController();
        const signal = options && options.signal || input && input.signal;
        const forwardAbort = () => abort.abort();
        if (signal) {
          if (signal.aborted) forwardAbort();
          else signal.addEventListener('abort', forwardAbort, { once: true });
        }
        let timedOut = false;
        let terminal = false;
        const timer = setTimeout(() => { timedOut = true; abort.abort(); }, 55000);
        try {
          const response = await fetchOriginal(input, Object.assign({}, options, { signal: abort.signal }));
          let result = null;
          try { result = await response.clone().json(); } catch (_) {}
          const state = result && ['waiting', 'success', 'expired', 'error'].includes(result.status) ? result.status : 'unknown';
          log('response', action, String(response.status) + ':' + state);
          if (button && button.isConnected) {
            terminal = !!(result && (result.terminal || state === 'expired' || state === 'success'));
            button.textContent = state === 'success' ? '登录成功' : terminal ? '请重新扫码' :
              !response.ok || !result || result.code || state === 'error' ? '确认失败，点击重试' : '尚未确认，点击重试';
          }
          return response;
        } catch (error) {
          log('failed', action, timedOut ? 'timeout' : 'network');
          if (button && button.isConnected) button.textContent = timedOut ? '确认超时，点击重试' : '确认失败，点击重试';
          if (timedOut) {
            message('登录确认超时，请检查网络后重试');
            throw new Error('登录确认超时，请检查网络后重试');
          }
          throw error;
        } finally {
          clearTimeout(timer);
          if (signal) signal.removeEventListener('abort', forwardAbort);
          if (button) { pending--; if (button.isConnected) button.disabled = terminal; }
        }
      };
      document.addEventListener('click', event => {
        const button = event.target && event.target.closest ? event.target.closest('#confirmLoginBtn') : null;
        if (!button || button.disabled) return;
        const before = requests;
        // Wait for the source handler to start its fetch before deciding that its task has disappeared.
        queueMicrotask(() => {
          if (requests !== before || pending || !button.isConnected) return;
          button.textContent = '请重新扫码';
          message('登录任务已结束，请重新点击扫码登录');
          log('ignored', 'poll', 'missing-task');
        });
      }, true);
    })();`;
  }
}
