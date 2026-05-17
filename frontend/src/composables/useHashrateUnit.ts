// Mirrors public/include/smarty_globals.inc.php::_hashrate_auto_modifier
// and the modifier-table consumed by sse-live.js. Input: hashrate in KH/s.
// Output: display value + unit string + multiplier (so callers can scale
// gauge max bounds the same way).
//
// Thresholds match the legacy PHP helper:
//   < 1_000          KH/s         multiplier 1
//   < 1_000_000      MH/s         multiplier 1e-3
//   < 1_000_000_000  GH/s         multiplier 1e-6
//   else             TH/s         multiplier 1e-9

interface Scale {
  thresholdKHs: number;
  multiplier: number;
  unit: string;
}

const SCALES: readonly Scale[] = [
  { thresholdKHs: 1_000,             multiplier: 1,    unit: 'KH/s' },
  { thresholdKHs: 1_000_000,         multiplier: 1e-3, unit: 'MH/s' },
  { thresholdKHs: 1_000_000_000,     multiplier: 1e-6, unit: 'GH/s' },
];

const TH_S: Scale = { thresholdKHs: Infinity, multiplier: 1e-9, unit: 'TH/s' };

export interface ScaledHashrate {
  value: number;
  unit: string;
  multiplier: number;
}

export function autoScaleHashrate(khs: number): ScaledHashrate {
  for (const scale of SCALES) {
    if (khs < scale.thresholdKHs) {
      return { value: khs * scale.multiplier, unit: scale.unit, multiplier: scale.multiplier };
    }
  }
  return { value: khs * TH_S.multiplier, unit: TH_S.unit, multiplier: TH_S.multiplier };
}
