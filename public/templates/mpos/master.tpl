<!doctype html>
<html lang="en">
<head>
	<meta charset="utf-8"/>
	<title>{$GLOBAL.website.title} Blakecoin {$smarty.request.page|escape|default:" mining pool"|capitalize}</title>
	
	<link rel="stylesheet" href="{$PATH}/css/theme.css" type="text/css" media="screen" />
	<link rel="stylesheet" href="{$PATH}/css/layout.css" type="text/css" media="screen" />
  <link rel="stylesheet" href="{$PATH}/css/fontello.css">
  <link rel="stylesheet" href="{$PATH}/css/animation.css">
  <!--[if IE 7]><link rel="stylesheet" href="css/fontello-ie7.css"><![endif]-->
	<link rel="stylesheet" href="{$PATH}/css/visualize.css" type="text/css" media="screen" />
	<link rel="stylesheet" href="{$PATH}/css/custom.css" type="text/css" media="screen" />
	<link rel="stylesheet" href="{$PATH}/css/jquery.jqplot.min.css" type="text/css" media="screen" />
  <!--[if lt IE 9]>
	<link rel="stylesheet" href="{$PATH}/css/ie.css" type="text/css" media="screen" />
	<script src="http://html5shim.googlecode.com/svn/trunk/html5.js"></script>
	<![endif]-->
	<script type="text/javascript" src="{$PATH}/js/jquery-2.0.3.min.js"></script>
	<script type="text/javascript" src="{$PATH}/js/jquery-migrate-1.2.1.min.js"></script>
	<script type="text/javascript" src="{$PATH}/js/hideshow.js" type="text/javascript"></script>
  <script type="text/javascript" src="{$PATH}/js/jquery.visualize.js"></script>
  <script type="text/javascript" src="{$PATH}/js/jquery.jqplot.min.js"></script>
	<script type="text/javascript" src="{$PATH}/js/jquery.tablesorter.min.js" type="text/javascript"></script>
	<script type="text/javascript" src="{$PATH}/js/jquery.tablesorter.pager.js" type="text/javascript"></script>
	<script type="text/javascript" src="{$PATH}/js/jquery.equalHeight.js"></script>
  <script type="text/javascript" src="{$PATH}/js/raphael.2.1.2.min.js"></script>
  <script type="text/javascript" src="{$PATH}/js/justgage.1.0.1.min.js"></script>
	<script type="text/javascript" src="{$PATH}/js/custom.js"></script>
	<script type="text/javascript" src="{$PATH}/js/theme.js"></script>
	<script type="text/javascript" src="{$PATH}/js/tinybox.js"></script>
	<script type="text/javascript" src="{$PATH}/../global/js/number_format.js"></script>
  <!--[if IE]><script type="text/javascript" src="{$PATH}/js/excanvas.js"></script><![endif]-->
  {literal}<script>
    var zxcvbnPath = "{/literal}{$PATH}{literal}/js/zxcvbn/zxcvbn.js";
  </script>{/literal}
  <script type="text/javascript" src="{$PATH}/js/pwcheck.js"></script>
    {if $GLOBAL.statistics.analytics.enabled}
      {$GLOBAL.statistics.analytics.code nofilter}
    {/if}

</head>
<body>
	<header id="header">
    {include file="global/header.tpl"}
	</header>
{if $MOTD_BANNER|default}
  <div id="bsx-motd-banner" class="bsx-motd-banner" role="status" aria-live="polite">
    <div class="bsx-motd-banner-inner">{$MOTD_BANNER nofilter}</div>
  </div>
{/if}
	<section id="secondary_bar">
    {include file="global/userinfo.tpl"}
    {include file="global/breadcrumbs.tpl"}
	</section>
	<aside id="sidebar" class="column">
    {include file="global/navigation.tpl"}
	</aside>
	<section id="main" class="column">
    {nocache}
    {if is_array($PAGE_POPUPS|default)}
      <div id="bsx-toast-container" aria-live="polite">
      {section name=popup loop=$PAGE_POPUPS}
        <div class="bsx-toast bsx-toast-{$PAGE_POPUPS[popup].TYPE|default:'info'}">
          {$PAGE_POPUPS[popup].CONTENT nofilter}
        </div>
      {/section}
      </div>
    {/if}
    {/nocache}
    <script>
      (function () {
        function ensureContainer() {
          var c = document.getElementById('bsx-toast-container');
          if (!c) {
            c = document.createElement('div');
            c.id = 'bsx-toast-container';
            c.setAttribute('aria-live', 'polite');
            document.body.appendChild(c);
          }
          return c;
        }
        function fade(el) {
          setTimeout(function () { el.classList.add('is-fading'); }, 4000);
          setTimeout(function () { if (el.parentNode) el.parentNode.removeChild(el); }, 4400);
        }
        window.bsxToast = function (html, type) {
          var c = ensureContainer();
          var el = document.createElement('div');
          el.className = 'bsx-toast bsx-toast-' + (type || 'info');
          el.innerHTML = html;
          c.appendChild(el);
          fade(el);
        };
        document.querySelectorAll('#bsx-toast-container .bsx-toast').forEach(fade);
      })();
    </script>
    <style>
      /* Global thin custom scrollbar — single source of truth so
         every page (legacy Smarty + v2 Vue) gets the same look
         instead of each component re-declaring the rules. Light-mode
         override below adjusts the thumb colour for white surfaces.
         WebKit (Chrome / Safari) uses ::-webkit-scrollbar; Firefox
         uses scrollbar-width / scrollbar-color. Both supported. */
      html { scrollbar-width: thin; scrollbar-color: rgba(255,255,255,.18) transparent; }
      ::-webkit-scrollbar { width: 8px; height: 8px; }
      ::-webkit-scrollbar-track { background: transparent; }
      ::-webkit-scrollbar-thumb {
        background-color: rgba(255,255,255,.18);
        border-radius: 4px;
        border: 2px solid transparent;
        background-clip: padding-box;
      }
      ::-webkit-scrollbar-thumb:hover { background-color: rgba(79,195,247,.45); }
      [data-theme="light"] html { scrollbar-color: rgba(0,0,0,.25) transparent; }
      [data-theme="light"] ::-webkit-scrollbar-thumb { background-color: rgba(0,0,0,.25); }
      [data-theme="light"] ::-webkit-scrollbar-thumb:hover { background-color: rgba(21,101,192,.55); }

      #bsx-toast-container {
        position: fixed;
        top: 24px;
        left: 50%;
        transform: translateX(-50%);
        z-index: 9999;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 8px;
        pointer-events: none;
        max-width: 90vw;
      }
      .bsx-toast {
        pointer-events: auto;
        padding: 10px 18px;
        border-radius: 6px;
        font-size: 13px;
        font-weight: 600;
        letter-spacing: 0.02em;
        box-shadow: 0 4px 18px rgba(0,0,0,0.35);
        border: 1px solid transparent;
        transition: opacity 350ms ease, transform 350ms ease;
        opacity: 1;
        transform: translateY(0);
      }
      .bsx-toast.is-fading { opacity: 0; transform: translateY(-8px); }
      .bsx-toast a { color: inherit; text-decoration: underline; }
      .bsx-toast-success { background: rgba(46, 125, 50, 0.95); border-color: rgba(181, 231, 160, 0.55); color: #ffffff; }
      .bsx-toast-info    { background: rgba(25, 118, 210, 0.95); border-color: rgba(79, 195, 247, 0.55); color: #ffffff; }
      .bsx-toast-warning { background: rgba(245, 124, 0, 0.95); border-color: rgba(255, 214, 110, 0.55); color: #ffffff; }
      .bsx-toast-errormsg,
      .bsx-toast-error   { background: rgba(198, 40, 40, 0.95); border-color: rgba(229, 115, 115, 0.55); color: #ffffff; }

      /* MotD banner — pinned across the top in "Always show" mode. */
      .bsx-motd-banner {
        background: rgba(25, 118, 210, 0.95);
        border-bottom: 1px solid rgba(79, 195, 247, 0.55);
        color: #ffffff;
        font-size: 13px;
        font-weight: 600;
        letter-spacing: 0.02em;
        text-align: center;
        padding: 8px 10px;
        box-shadow: 0 1px 6px rgba(0, 0, 0, 0.25);
      }
      .bsx-motd-banner-inner { max-width: none; margin: 0; }
      .bsx-motd-banner a { color: inherit; text-decoration: underline; }
      .bsx-motd-banner p { margin: 0; }
      .bsx-motd-banner p + p { margin-top: 4px; }
      [data-theme="light"] .bsx-motd-banner {
        background: rgba(25, 118, 210, 0.97);
        border-bottom-color: rgba(21, 101, 192, 0.65);
      }
    </style>
    {if $CONTENT != "empty" && $CONTENT != ""}
      {if file_exists($smarty.current_dir|cat:"/$PAGE/$ACTION/$CONTENT")}
        {include file="$PAGE/$ACTION/$CONTENT"}
      {else}
        Missing template for this page
      {/if}
    {/if}
		<div class="spacer"></div>
	</section>
  <footer class="footer">
    {include file="global/footer.tpl"}
  </footer>
</body>
</html>
