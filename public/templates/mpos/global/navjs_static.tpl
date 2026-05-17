<script>
{literal}
$(document).ready(function(){
  // Auto-scale a raw KH/s value into the most readable unit.
  function fmtHashrate(rawKHs) {
    rawKHs = +rawKHs || 0;
    var unit = 'KH/s', div = 1;
    if      (rawKHs >= 1e9) { unit = 'TH/s'; div = 1e9; }
    else if (rawKHs >= 1e6) { unit = 'GH/s'; div = 1e6; }
    else if (rawKHs >= 1e3) { unit = 'MH/s'; div = 1e3; }
    var scaled = rawKHs / div;
    return {
      scaled: +scaled.toFixed(2),
      unit:   unit,
      max:    Math.max(2, Math.round(scaled * 2))
    };
  }

  var g1 = new JustGage({
    id: "mr",
    value: parseFloat({/literal}{$GLOBAL.workers}{literal}).toFixed(0),
    min: 0,
    max: Math.max(2, Math.round({/literal}{$GLOBAL.workers}{literal} * 2)),
    title: "Miners",
    gaugeColor: '#6f7a8a',
    valueFontColor: '#888',
    titleFontColor: '#cdd',
    labelFontColor: '#b3b3b3',
    label: "Active Miners",
    relativeGaugeSize: true,
    showMinMax: true,
    showInnerShadow: true,
    shadowOpacity: 0.8,
    shadowSize: 0,
    shadowVerticalOffset: 10
  });

  var fmt = fmtHashrate({/literal}{$GLOBAL.rawhashrate|default:0}{literal});
  var g2 = new JustGage({
    id: "hr",
    value: fmt.scaled,
    min: 0,
    max: fmt.max,
    title: "Pool Hashrate",
    gaugeColor: '#6f7a8a',
    valueFontColor: '#888',
    titleFontColor: '#cdd',
    labelFontColor: '#b3b3b3',
    label: fmt.unit,
    relativeGaugeSize: true,
    showMinMax: true,
    showInnerShadow: true,
    shadowOpacity: 0.8,
    shadowSize: 0,
    shadowVerticalOffset: 10
  });
});
{/literal}
</script>
