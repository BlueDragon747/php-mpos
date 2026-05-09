{* Per-coin admin wallet page — same v2 wrapper as the BLC route. The
   per-slot controller (e.g. wallet_mm.inc.php) sets the same Smarty
   variables (BALANCE / LOCKED / UNCONFIRMED / NEWMINT / COININFO /
   COIN_TICKER / COIN_NAME) so the shared template renders identically. *}
{include file="admin/wallet/default.tpl"}
