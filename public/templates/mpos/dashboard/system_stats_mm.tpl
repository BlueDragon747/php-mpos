 <article class="module width_quarter">
   <header><h3>{$GLOBAL.config.currency_mm} {$GLOBAL.config.payout_system_mm|capitalize} Stats</h3>{if $COIN_ICON_MM|default:""}<img src="{$COIN_ICON_MM|escape}" alt="{$GLOBAL.config.currency_mm|escape}" width="24" height="24" style="float:right;margin:7px 8px 0 0;object-fit:contain;opacity:0.95;border-radius:4px;" loading="lazy" onerror="this.style.display='none'">{/if}</header>
   <div class="module_content">
     <table width="100%">
       <tbody>
{if $GLOBAL.config.payout_system_mm == 'pplns'}
         <tr>
           <td><b>PPLNS Target</b></td>
           <td id="b-pplns" class="right">{$GLOBAL.pplns.target_mm}</td>
         </tr>
{/if}
         {include file="dashboard/round_shares_mm.tpl"}
         {include file="dashboard/payout_estimates_mm.tpl"}
         {include file="dashboard/network_info_mm.tpl"}
       </tbody>
      </table>
    </div>
 </article>

