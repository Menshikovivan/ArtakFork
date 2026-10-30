import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({ execute: vi.fn(), modal: vi.fn() }));
vi.mock('../../../helpers', () => ({ executeShellCommand: mocks.execute }));
import { showSubscriptionChangeReport } from './subscriptionChangeReport';

describe('subscription update report', () => {
  beforeEach(() => {
    mocks.execute.mockReset();
    mocks.modal.mockReset();
    vi.stubGlobal('E', (tag: string, props: unknown, children: unknown) => ({
      tag,
      props,
      children,
    }));
    vi.stubGlobal('ui', { showModal: mocks.modal, hideModal: vi.fn() });
  });

  it('shows only the report belonging to the completed job and labels failed apply', async () => {
    const report = {
      job_id: 'job-1',
      sources: [
        {
          section: '2',
          source: 1,
          status: 'updated',
          baseline: false,
          added: ['Node A'],
          removed: [],
          changed: [],
          skipped: 1,
          skip_reasons: { unsupported_protocol: 1 },
        },
      ],
    };
    mocks.execute.mockResolvedValue({
      code: 0,
      stdout: JSON.stringify(report),
    });
    await showSubscriptionChangeReport('other-job', false);
    expect(mocks.modal).not.toHaveBeenCalled();
    await showSubscriptionChangeReport('job-1', false);
    const shown = JSON.stringify(mocks.modal.mock.calls);
    expect(shown).toContain('may not have been applied');
    expect(shown).toContain('Node A');
    expect(shown).toContain('Unsupported protocol');
  });

  it('does not block an update if report reading fails', async () => {
    mocks.execute.mockRejectedValue(new Error('unavailable'));
    await expect(
      showSubscriptionChangeReport('job-1', true),
    ).resolves.toBeUndefined();
    expect(mocks.modal).not.toHaveBeenCalled();
  });
});
