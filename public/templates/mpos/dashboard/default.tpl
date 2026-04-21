{if $smarty.session.AUTHENTICATED|default}
  {include file="dashboard/overview.tpl"}
  {include file="dashboard/account_data.tpl"}
  {include file="dashboard/system_stats.tpl"}
  {include file="dashboard/system_stats_mm.tpl"}

  {include file="dashboard/system_stats_mm1.tpl"}
  {include file="dashboard/system_stats_mm3.tpl"}
  {include file="dashboard/system_stats_mm4.tpl"}
  {include file="dashboard/system_stats_mm5.tpl"}

  {if !$DISABLED_DASHBOARD and !$DISABLED_DASHBOARD_API}
  {include file="dashboard/js_api.tpl"}
  {else}
  {include file="dashboard/js_static.tpl"}
  {/if}
{/if}
