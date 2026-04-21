 <article class="module width_quarter">
   <header><h3>{$GLOBAL.config.currency_mm4} {$GLOBAL.config.payout_system_mm4|capitalize} Stats</h3></header>
   <div class="module_content">
     <table width="100%">
       <tbody>
{if $GLOBAL.config.payout_system_mm4 == 'pplns'}
         <tr>
           <td><b>PPLNS Target</b></td>
           <td id="b-pplns" class="right">{$GLOBAL.pplns.target_mm4}</td>
         </tr>
{/if}
         {include file="dashboard/round_shares_mm4.tpl"}
         {include file="dashboard/payout_estimates_mm4.tpl"}
         {include file="dashboard/network_info_mm4.tpl"}
       </tbody>
      </table>
    </div>
 </article>

