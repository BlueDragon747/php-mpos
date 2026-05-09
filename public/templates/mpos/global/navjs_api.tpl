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

  // JustGage 1.0.1 has no label setter; rebuild the gauge on a unit
  // boundary cross so the KH/s → GH/s transition shows correctly.
  var g1, g2, currentUnit = null;

  function buildHashrateGauge(rawKHs) {
    var fmt = fmtHashrate(rawKHs);
    var hrEl = document.getElementById('hr');
    if (hrEl) hrEl.innerHTML = '';
    g2 = new JustGage({
      id: 'hr',
      value: fmt.scaled,
      min: 0,
      max: fmt.max,
      title: 'Pool Hashrate',
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
    currentUnit = fmt.unit;
  }

  g1 = new JustGage({
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

  buildHashrateGauge({/literal}{$GLOBAL.rawhashrate|default:0}{literal});

  // Ajax API URL
  var url = "{/literal}{$smarty.server.SCRIPT_NAME}?page=api&action=getnavbardata{literal}";

  // Refresh: read raw KH/s from data.raw.pool.hashrate so JS owns
  // scaling end-to-end. Rebuild on a unit-boundary cross.
  function refreshInformation(data) {
    var workers = parseFloat(data.getnavbardata.data.pool.workers).toFixed(0);
    g1.refresh(workers);

    var rawKHs = parseFloat(
      (data.getnavbardata.data.raw && data.getnavbardata.data.raw.pool &&
       data.getnavbardata.data.raw.pool.hashrate) ||
      data.getnavbardata.data.pool.hashrate || 0
    );
    var fmt = fmtHashrate(rawKHs);
    if (fmt.unit !== currentUnit) {
      buildHashrateGauge(rawKHs);
    } else {
      g2.refresh(fmt.scaled, fmt.max);
    }
  }

  (function worker() {
    $.ajax({
      url: url,
      dataType: 'json',
      success: function(data) { refreshInformation(data); },
      complete: function() {
        setTimeout(worker, {/literal}{($GLOBAL.config.statistics_ajax_refresh_interval * 1000)|default:"1000"}{literal})
      }
    });
  })();
});
{/literal}
</script>
