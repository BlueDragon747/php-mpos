    <li class="icon-home"><a href="{$smarty.server.SCRIPT_NAME}">Home</a></li>
    {if $smarty.session.AUTHENTICATED|default:"0" == 1}
    <h3>My Account</h3>
    <ul class="toggle">
      <li class="icon-gauge"><a href="{$smarty.server.SCRIPT_NAME}?page=dashboard">Dashboard</a></li>
      <li class="icon-user"><a href="{$smarty.server.SCRIPT_NAME}?page=account&action=edit">Edit Account</a></li>
      <li class="icon-photo"><a href="{$smarty.server.SCRIPT_NAME}?page=account&action=workers">My Workers</a></li>
      <li class="icon-indent-left"><a href="{$smarty.server.SCRIPT_NAME}?page=account&action=transactions">{$GLOBAL.config.currency} Transactions</a></li>
      <li class="icon-indent-left"><a href="{$smarty.server.SCRIPT_NAME}?page=account&action=transactions_mm">{$GLOBAL.config.currency_mm} Transactions</a></li>
      <li class="icon-indent-left"><a href="{$smarty.server.SCRIPT_NAME}?page=account&action=transactions_mm1">{$GLOBAL.config.currency_mm1} Transactions</a></li>
      <li class="icon-indent-left"><a href="{$smarty.server.SCRIPT_NAME}?page=account&action=transactions_mm3">{$GLOBAL.config.currency_mm3} Transactions</a></li>
      <li class="icon-indent-left"><a href="{$smarty.server.SCRIPT_NAME}?page=account&action=transactions_mm4">{$GLOBAL.config.currency_mm4} Transactions</a></li>
      <li class="icon-indent-left"><a href="{$smarty.server.SCRIPT_NAME}?page=account&action=transactions_mm5">{$GLOBAL.config.currency_mm5} Transactions</a></li>
    {if !$GLOBAL.config.disable_notifications}<li class="icon-megaphone"><a href="{$smarty.server.SCRIPT_NAME}?page=account&action=notifications">Notifications</a></li>{/if}
    {if !$GLOBAL.config.disable_invitations}<li class="icon-plus"><a href="{$smarty.server.SCRIPT_NAME}?page=account&action=invitations">Invitations</a></li>{/if}
      <li class="icon-barcode"><a href="{$smarty.server.SCRIPT_NAME}?page=account&action=qrcode">QR Codes</a></li>
    </ul>
    </li>
    {/if}
    {if $smarty.session.AUTHENTICATED|default:"0" == 1 && $GLOBAL.userdata.is_admin == 1}
    <h3>Admin Panel</h3>
    <ul class="toggle">
      <li class="icon-gauge"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=dashboard">Dashboard</a></li>
      <li class="icon-bell"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=monitoring">Monitoring</a></li>
      <li class="icon-torso"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=user">User Info</a></li>
      <li class="icon-money"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=wallet">{$GLOBAL.config.currency} Wallet Info</a></li>
      <li class="icon-money"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=wallet_mm">{$GLOBAL.config.currency_mm} Wallet_mm Info</a></li>
      <li class="icon-money"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=wallet_mm1">{$GLOBAL.config.currency_mm1} Wallet_mm1 Info</a></li>
      <li class="icon-money"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=wallet_mm3">{$GLOBAL.config.currency_mm3} Wallet_mm3 Info</a></li>
      <li class="icon-money"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=wallet_mm4">{$GLOBAL.config.currency_mm4} Wallet_mm4 Info</a></li>
      <li class="icon-money"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=wallet_mm5">{$GLOBAL.config.currency_mm5} Wallet_mm5 Info</a></li>
      <li class="icon-exchange"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=transactions">{$GLOBAL.config.currency} Transactions</a></li>
      <li class="icon-exchange"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=transactions_mm">{$GLOBAL.config.currency_mm} Transactions_mm</a></li>
      <li class="icon-exchange"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=transactions_mm1">{$GLOBAL.config.currency_mm1} Transactions_mm1</a></li>
      <li class="icon-exchange"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=transactions_mm3">{$GLOBAL.config.currency_mm3} Transactions_mm3</a></li>
      <li class="icon-exchange"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=transactions_mm4">{$GLOBAL.config.currency_mm4} Transactions_mm4</a></li>
      <li class="icon-exchange"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=transactions_mm5">{$GLOBAL.config.currency_mm5} Transactions_mm5</a></li>
      <li class="icon-cog"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=settings">Settings</a></li>
      <li class="icon-doc"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=news">News</a></li>
      <li class="icon-chart"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=reports">Reports</a></li>
      <li class="icon-photo"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=poolworkers">Pool Workers</a></li>
      <li class="icon-pencil"><a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=templates">Templates</a></li>
    </ul>
    {/if}
    {if $smarty.session.AUTHENTICATED|default}
    <h3>Statistics</h3>
    <ul class="toggle">
      <li class="icon-align-left"><a href="{$smarty.server.SCRIPT_NAME}?page=statistics&action=pool">{$GLOBAL.config.currency} Pool</a></li>
      <li class="icon-th-large"><a href="{$smarty.server.SCRIPT_NAME}?page=statistics&action=blocks">{$GLOBAL.config.currency} Blocks</a></li>
      <li class="icon-chart"><a href="{$smarty.server.SCRIPT_NAME}?page=statistics&action=graphs">Graphs</a></li>
      <li class="icon-record"><a href="{$smarty.server.SCRIPT_NAME}?page=statistics&action=round">{$GLOBAL.config.currency} Round</a></li>
      <li class="icon-search"><a href="{$smarty.server.SCRIPT_NAME}?page=statistics&action=blockfinder">{$GLOBAL.config.currency} Finder</a></li>
      {if $GLOBAL.config.monitoring_uptimerobot_api_keys|default:"0"}<li class="icon-bell"><a href="{$smarty.server.SCRIPT_NAME}?page=statistics&action=uptime">Uptime</a></li>{/if}
    </ul>
    {else}
    <h3>Statistics</h3>
    <ul class="toggle">
     {if $GLOBAL.acl.pool.statistics}
     <li class="icon-align-left"><a href="{$smarty.server.SCRIPT_NAME}?page=statistics&action=pool">{$GLOBAL.config.currency} Pool</a></li>
     {else}
     <li class="icon-align-left"><a href="{$smarty.server.SCRIPT_NAME}?page=statistics">Statistics</a>
     {/if}
     {if $GLOBAL.acl.block.statistics}
     <li class="icon-th-large"><a href="{$smarty.server.SCRIPT_NAME}?page=statistics&action=blocks">{$GLOBAL.config.currency} Blocks</a></li>
     {/if}
     {if $GLOBAL.acl.round.statistics}
     <li class="icon-chart"><a href="{$smarty.server.SCRIPT_NAME}?page=statistics&action=round">{$GLOBAL.config.currency} Round</a></li>
     {/if}
    </ul>
    {/if}
    <h3>Help</h3>
    <ul class="toggle">
      <li class="icon-desktop"><a href="{$smarty.server.SCRIPT_NAME}?page=gettingstarted">Getting Started</a></li>
      {if !$GLOBAL.website.about.disabled}
      <li class="icon-doc"><a href="{$smarty.server.SCRIPT_NAME}?page=about&action=pool">About</a></li>
      {/if}
      {if !$GLOBAL.website.donors.disabled}
      <li class="icon-money"><a href="{$smarty.server.SCRIPT_NAME}?page=about&action=donors">Donors</a></li>
      {/if}
    </ul>
    <h3>Other</h3>
    <ul class="toggle">
      {if $smarty.session.AUTHENTICATED|default:"0" == 1}
      {if $GLOBAL.config.disable_contactform|default:"0" != 1}
      <li class="icon-mail"><a href="{$smarty.server.SCRIPT_NAME}?page=contactform">Contact</a></li>
      {/if}
      <li class="icon-off"><a href="{$smarty.server.SCRIPT_NAME}?page=logout">Logout</a></li>
      {else}
      <li class="icon-login"><a href="{$smarty.server.SCRIPT_NAME}?page=login">Login</a></li>
      <li class="icon-pencil"><a href="{$smarty.server.SCRIPT_NAME}?page=register">Sign Up</a></li>
      {if $GLOBAL.config.disable_contactform|default:"0" != 1}
      <li class="icon-mail"><a href="{$smarty.server.SCRIPT_NAME}?page=contactform">Contact</a></li>
      {/if}
      <li class="icon-doc"><a href="{$smarty.server.SCRIPT_NAME}?page=tac">Terms and Conditions</a></li>
      {/if}
      <li class="theme-toggle-item"><a href="#" id="theme-toggle-link" onclick="ThemeManager.toggle(); return false;">Dark Mode</a></li>
    </ul>
    {if $smarty.session.AUTHENTICATED|default:"0" == 1}
     <br />
    {else}
    <ul>
     <center>
      <div style="display: inline-block;">
      <i><u><b><font size="2">LIVE STATS</font></b></u></i>
      <div id="mr" style="width:180px; height:120px;"></div>
      <div id="hr" style="width:180px; height:120px;"></div>
      </div>
     </center>
    </ul>
    {if !$GLOBAL.website.api.disabled && !$GLOBAL.config.disable_navbar && !$GLOBAL.config.disable_navbar_api}
      {include file="global/navjs_api.tpl"}
    {else}
      {include file="global/navjs_static.tpl"}
    {/if}
    {/if}
