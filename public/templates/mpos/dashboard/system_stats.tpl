 <article class="module width_quarter">
   <header><h3>{$GLOBAL.config.currency} {$GLOBAL.config.payout_system|capitalize} Stats</h3></header>
   <div class="module_content">
     <table width="100%">
       <tbody>
{if $GLOBAL.config.payout_system == 'pplns'}
         <tr>
           <td><b>PPLNS Target</b></td>
           <td id="b-pplns" class="right">{$GLOBAL.pplns.target}</td>
         </tr>
{/if}
         {include file="dashboard/round_shares.tpl"}
         {include file="dashboard/payout_estimates.tpl"}
         {include file="dashboard/network_info.tpl"}
       </tbody>
      </table>
    </div>
 </article>

