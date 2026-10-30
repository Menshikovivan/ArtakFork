import { ForkopShellMethods } from '../../methods';
import { Forkop } from '../../types';

export function showServiceCheck(outbound: Forkop.Outbound) {
  const select = E('select', { class: 'cbi-input-select' }, [
    E('option', { value: 'chatgpt' }, 'ChatGPT'),
    E('option', { value: 'gemini' }, 'Gemini'),
    E('option', { value: 'discord' }, 'Discord'),
  ]) as HTMLSelectElement;
  const result = E('p', { role: 'status' }, '');
  const test = E(
    'button',
    {
      type: 'button',
      class: 'btn cbi-button cbi-button-action',
      click: async () => {
        test.disabled = true;
        result.textContent = _('Checking HTTPS connection…');
        try {
          const response = await ForkopShellMethods.checkService(
            select.value,
            outbound.code,
          );
          if (response.success && response.data.success) {
            result.textContent = _(
              'HTTPS response received through the selected proxy. HTTP status, region and sign-in are not verified.',
            );
          } else {
            result.textContent = _(
              'Check failed. The node, TLS connection or service may be unavailable.',
            );
          }
        } catch {
          result.textContent = _(
            'Check failed. The node, TLS connection or service may be unavailable.',
          );
        } finally {
          test.disabled = false;
        }
      },
    },
    _('Check service'),
  ) as HTMLButtonElement;
  ui.showModal(
    `${_('Check service')}: ${outbound.displayName}`,
    E('div', {}, [
      E(
        'p',
        {},
        _(
          'The check uses the selected node or the currently active node in the selected group.',
        ),
      ),
      select,
      E(
        'p',
        {},
        _(
          'An HTTPS response can include an error or access restriction; this does not test your account or all service endpoints.',
        ),
      ),
      result,
      test,
      E(
        'button',
        { type: 'button', class: 'btn', click: () => ui.hideModal() },
        _('Close'),
      ),
    ]),
  );
}
