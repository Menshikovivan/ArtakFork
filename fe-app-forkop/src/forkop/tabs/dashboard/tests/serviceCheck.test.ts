import { beforeEach, describe, expect, it, vi } from 'vitest';

const { checkService } = vi.hoisted(() => ({ checkService: vi.fn() }));
vi.mock('../../../methods', () => ({ ForkopShellMethods: { checkService } }));
import { showServiceCheck } from '../serviceCheck';

type Node = {
  type: string;
  attributes: Record<string, unknown>;
  children: Node[] | string;
  textContent: string;
  disabled: boolean;
  value: string;
};

let modal: Node;
beforeEach(() => {
  checkService.mockReset();
  vi.stubGlobal('_', (text: string) => text);
  vi.stubGlobal(
    'E',
    (
      type: string,
      attributes: Record<string, unknown>,
      children: Node[] | string,
    ) => ({
      type,
      attributes,
      children,
      textContent: '',
      disabled: false,
      value: type === 'select' ? 'chatgpt' : '',
    }),
  );
  vi.stubGlobal('ui', {
    showModal: (_title: string, body: Node) => {
      modal = body;
    },
    hideModal: () => {},
  });
});

describe('service check', () => {
  it('tests the requested group and explains what an HTTPS response proves', async () => {
    checkService.mockResolvedValue({ success: true, data: { success: true } });
    showServiceCheck({
      code: 'group-tag',
      displayName: 'Group',
      type: 'URLTest',
      selected: true,
      latency: 1,
    });
    const children = modal.children as Node[];
    const result = children[3];
    const button = children[4];
    await (button.attributes.click as () => Promise<void>)();
    expect(checkService).toHaveBeenCalledWith('chatgpt', 'group-tag');
    expect(result.textContent).toContain(
      'HTTP status, region and sign-in are not verified',
    );
    expect(button.disabled).toBe(false);
  });

  it('shows failure without claiming the service is down', async () => {
    checkService.mockResolvedValue({ success: true, data: { success: false } });
    showServiceCheck({
      code: 'node',
      displayName: 'Node',
      type: 'VLESS',
      selected: true,
      latency: 1,
    });
    const children = modal.children as Node[];
    await (children[4].attributes.click as () => Promise<void>)();
    expect(children[3].textContent).toContain('may be unavailable');
  });
});
