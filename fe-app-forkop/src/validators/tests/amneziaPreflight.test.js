import { describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('../../../../luci-app-forkop/htdocs/luci-static/resources/view/forkop/section.js', import.meta.url), 'utf8');
const snippet = source.slice(source.indexOf('const awgPreflightRpc ='), source.indexOf('const ACTION_PROVIDERS_AVAILABILITY_EVENT'));

function mount(rpcResult) {
  const nodes = [];
  const rpcCall = vi.fn().mockResolvedValue(rpcResult);
  const E = (tag, attrs = {}, text = '') => {
    const node = { tag, ...attrs, textContent: typeof text === 'string' ? text : '', handlers: {}, addEventListener(name, fn) { this.handlers[name] = fn; } };
    nodes.push(node);
    return node;
  };
  const ui = { showModal: vi.fn(), hideModal: vi.fn() };
  runInNewContext(`${snippet}\nshowAmneziaPreflight();`, { rpc: { declare: () => rpcCall }, E, ui });
  return { nodes, rpcCall, ui };
}

describe('AmneziaWG preflight UI', () => {
  it('refuses oversized files without sending them', async () => {
    const { nodes, rpcCall } = mount({ ok: true });
    const input = nodes.find((n) => n.tag === 'input');
    const check = nodes.find((n) => n.tag === 'button' && n.textContent === 'Проверить файл');
    input.files = [{ size: 262145, text: vi.fn() }];
    input.handlers.change();
    await check.handlers.click();
    expect(check.disabled).toBe(true);
    expect(rpcCall).not.toHaveBeenCalled();
  });

  it('sends the config via RPC and states explicitly that no connection was created', async () => {
    const { nodes, rpcCall, ui } = mount({ ok: true, peer_count: 1 });
    const input = nodes.find((n) => n.tag === 'input');
    const check = nodes.find((n) => n.tag === 'button' && n.textContent === 'Проверить файл');
    const status = nodes.find((n) => n.role === 'status');
    input.files = [{ size: 6, text: async () => 'secret' }];
    input.handlers.change();
    expect(check.disabled).toBe(false);
    await check.handlers.click();
    expect(rpcCall).toHaveBeenCalledWith('secret');
    expect(status.textContent).toContain('Подключение не создано');
    expect(status.textContent).not.toContain('secret');
    expect(ui.showModal.mock.calls[0][1][0].textContent).toContain('не импортирует');
  });
});
