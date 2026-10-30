import { executeShellCommand } from '../../../helpers';

interface SourceReport {
  section: string;
  source: number;
  status: string;
  baseline: boolean;
  added: string[];
  removed: string[];
  changed: Array<{ before: string; after: string; kind: string }>;
  skipped: number;
  skip_reasons: Record<string, number>;
}

function names(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === 'string')
    : [];
}

function linesForSource(value: SourceReport): string[] {
  const result = [
    `${_('Rule')}: ${value.section} · ${_('Source')}: ${value.source}`,
  ];
  if (value.status === 'failed') {
    result.push(_('Source update failed; see the log for details'));
    return result;
  }
  if (value.baseline)
    result.push(_('First import; no previous snapshot to compare'));
  for (const [label, items] of [
    [_('Added'), names(value.added)],
    [_('Removed'), names(value.removed)],
  ] as Array<[string, string[]]>) {
    if (items.length) result.push(`${label}: ${items.join(', ')}`);
  }
  if (Array.isArray(value.changed)) {
    for (const change of value.changed) {
      if (typeof change.before !== 'string' || typeof change.after !== 'string')
        continue;
      result.push(
        change.kind === 'renamed'
          ? `${_('Renamed')}: ${change.before} → ${change.after}`
          : `${_('Connection settings changed')}: ${change.after}`,
      );
    }
  }
  if (value.skipped > 0) {
    result.push(`${_('Skipped entries')}: ${value.skipped}`);
    const reasons = value.skip_reasons || {};
    for (const [key, label] of [
      ['unsupported_protocol', _('Unsupported protocol')],
      ['missing_protocol', _('Missing protocol')],
      ['invalid_parameters', _('Invalid or unsupported parameters')],
    ]) {
      if (Number(reasons[key]) > 0) result.push(`${label}: ${reasons[key]}`);
    }
    if (!Object.values(reasons).some((count) => Number(count) > 0))
      result.push(_('Detailed skip reason is unavailable for this format'));
  }
  if (result.length === 1) result.push(_('No proxy changes'));
  return result;
}

export async function showSubscriptionChangeReport(
  jobId: string,
  applied: boolean,
) {
  try {
    const response = await executeShellCommand({
      command: '/usr/bin/forkop',
      args: ['subscription_update_report'],
    });
    if (response.code || !response.stdout) return;
    const report = JSON.parse(response.stdout) as {
      job_id?: string;
      sources?: SourceReport[];
    };
    if (
      report.job_id !== jobId ||
      !Array.isArray(report.sources) ||
      !report.sources.length
    )
      return;
    const nodes = report.sources.flatMap((source) =>
      linesForSource(source).map((line) => E('p', {}, line)),
    );
    ui.showModal(
      _('Subscription update report'),
      E('div', {}, [
        E(
          'p',
          {},
          applied
            ? _(
                'Update completed. The report shows downloaded subscription data; individual sources may have failed.',
              )
            : _(
                'Update failed. The report shows downloaded data, which may not have been applied.',
              ),
        ),
        ...nodes,
        E('button', { class: 'btn', click: () => ui.hideModal() }, _('Close')),
      ]),
    );
  } catch {
    // A report is optional and never changes the result of the update.
  }
}
