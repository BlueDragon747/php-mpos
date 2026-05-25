 <article class="module width_quarter">
   <header><h3>{$GLOBAL.config.currency_mm5} {$GLOBAL.config.payout_system_mm5|capitalize} Stats</h3>{if $COIN_ICON_MM5|default:""}<img src="{$COIN_ICON_MM5|escape}" data-fallback="{$COIN_ICON_MM5_FALLBACK|default:""|escape}" alt="{$GLOBAL.config.currency_mm5|escape}" width="24" height="24" style="float:right;margin:7px 8px 0 0;object-fit:contain;opacity:0.95;border-radius:4px;" loading="lazy" onerror="if (this.dataset.fallback && this.dataset.fallbackApplied !== '1') { this.dataset.fallbackApplied = '1'; this.src = this.dataset.fallback; } else { this.style.display='none'; }">{/if}</header>
   <div class="module_content">
     <table width="100%">
       <tbody>
{if $GLOBAL.config.payout_system_mm5 == 'pplns'}
         <tr>
           <td><b>PPLNS Target</b></td>
           <td id="b-pplns" class="right">{$GLOBAL.pplns.target_mm5}</td>
         </tr>
{/if}
         {include file="dashboard/round_shares_mm5.tpl"}
         {include file="dashboard/payout_estimates_mm5.tpl"}
         {include file="dashboard/network_info_mm5.tpl"}
       </tbody>
      </table>
    </div>
 </article>
