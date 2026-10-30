// Translate known Forkop messages; preserve the original log for diagnostics.
export function getLogErrorMessage(line: string): string | null {
  const emptyGroup = line.match(
    /URLTest group '([^']*)' in rule '([^']*)' has no usable proxy outbounds after filtering(?:; filter mode: ([^;]*); available server names: (\[[^\n]*\]))?/,
  );
  if (emptyGroup) {
    let message = _(
      'No usable servers remain in URLTest group %s of section %s. Check the selection filter or configure a priority group with a backup server.',
    )
      .replace('%s', emptyGroup[1])
      .replace('%s', emptyGroup[2]);
    if (emptyGroup[3]) {
      const modes: Record<string, string> = {
        disabled: _('All servers'),
        include: _('Only selected'),
        exclude: _('All except selected'),
        mixed: _('Only selected except exclusions'),
      };
      message +=
        ' ' +
        _('Filter mode: %s.').replace(
          '%s',
          modes[emptyGroup[3]] || emptyGroup[3],
        );
    }
    if (emptyGroup[4]) {
      try {
        const names: unknown = JSON.parse(emptyGroup[4]);
        if (
          Array.isArray(names) &&
          names.every((name) => typeof name === 'string')
        ) {
          message +=
            ' ' +
            (names.length
              ? _('Available servers: %s.').replace('%s', names.join(', '))
              : _('No server names are available to display.'));
        }
      } catch {
        // The original line remains available in the technical details.
      }
    }
    return message;
  }
  if (
    line.includes('WhatsApp real DNS requires downloaded Meta subnet rules')
  ) {
    return _(
      'Meta subnet lists for WhatsApp are missing. Download the Meta lists and apply again, or turn off real IPs for WhatsApp.',
    );
  }
  if (line.includes('WhatsApp real DNS requires the Meta community list')) {
    return _(
      'WhatsApp real IPs require an enabled routing section with Meta and no device or port filters. Restore Meta or turn off real IPs for WhatsApp before saving. Otherwise Forkop cannot start after a reboot.',
    );
  }
  const space = line.match(
    /Not enough (flash space|temporary memory) for (Forkop update and rollback|sing-box): (?:conservative installation reserve needs|need) (\d+) KiB free, have (\d+) KiB/,
  );
  if (space) {
    const template =
      space[1] === 'flash space'
        ? space[2] === 'sing-box'
          ? _(
              'Not enough storage for sing-box installation. Required reserve: %s KiB; available: %s KiB.',
            )
          : _(
              'Not enough storage for Forkop update and rollback. Required reserve: %s KiB; available: %s KiB.',
            )
        : _(
            'Not enough temporary memory. Required: %s KiB; available: %s KiB.',
          );
    return template.replace('%s', space[3]).replace('%s', space[4]);
  }
  if (
    line.includes(
      'Forkop startup retry suppressed because the failure requires configuration or operator action',
    )
  ) {
    return _(
      'Automatic restart is paused. Check the configuration and the startup error in the logs.',
    );
  }
  if (line.includes('Generated sing-box configuration is invalid')) {
    return _(
      'The generated sing-box configuration is invalid. See technical details for the validation error.',
    );
  }
  const phase = line.match(
    /Startup phase '([^']+)' failed with exit status (\d+)/,
  );
  if (phase) {
    return _('Startup phase %s failed (exit code %s).')
      .replace('%s', phase[1])
      .replace('%s', phase[2]);
  }
  if (line.includes('Forkop automatic recovery attempt failed')) {
    return _('Automatic recovery failed. Check the startup error in the logs.');
  }
  return null;
}
