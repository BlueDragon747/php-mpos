{* Admin Transactions page — uses the same v2 wrapper as the user-facing
   transactions route. The admin controller calls
   include/pages/account/_transactions_v2.inc.php with $tx_v2_page='admin'
   so the SPA's form action and Username column flip on accordingly. *}
{include file="account/transactions/default.tpl"}
