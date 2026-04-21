-- phpMyAdmin SQL Dump
-- version 4.1.14
-- http://www.phpmyadmin.net
--
-- Host: localhost
-- Generation Time: May 10, 2014 at 10:46 AM
-- Server version: 5.5.34-0ubuntu0.12.04.1
-- PHP Version: 5.3.10-1ubuntu3.9

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;

--
-- Database: `mpos`
--

-- --------------------------------------------------------

--
-- Table structure for table `accounts`
--

CREATE TABLE IF NOT EXISTS `accounts` (
  `id` int(255) NOT NULL AUTO_INCREMENT,
  `is_admin` tinyint(1) NOT NULL DEFAULT '0',
  `is_anonymous` tinyint(1) NOT NULL DEFAULT '0',
  `no_fees` tinyint(1) NOT NULL DEFAULT '0',
  `username` varchar(40) NOT NULL,
  `pass` varchar(255) NOT NULL,
  `email` varchar(255) DEFAULT NULL COMMENT 'Assocaited email: used for validating users, and re-setting passwords',
  `notify_email` varchar(255) DEFAULT NULL,
  `loggedIp` varchar(255) DEFAULT NULL,
  `is_locked` tinyint(1) NOT NULL DEFAULT '0',
  `failed_logins` int(5) unsigned DEFAULT '0',
  `failed_pins` int(5) unsigned DEFAULT '0',
  `signup_timestamp` int(10) DEFAULT '0',
  `last_login` int(10) DEFAULT NULL,
  `pin` varchar(255) NOT NULL COMMENT 'four digit pin to allow account changes',
  `api_key` varchar(255) DEFAULT NULL,
  `token` varchar(65) DEFAULT NULL,
  `donate_percent` float DEFAULT '0',
  `ap_threshold` float DEFAULT '0',
  `coin_address` varchar(255) DEFAULT NULL,
  `coin_address_mm` varchar(255) DEFAULT NULL,
  `coin_address_mm1` varchar(255) DEFAULT NULL,
  `coin_address_mm2` varchar(255) DEFAULT NULL,
  `coin_address_mm3` varchar(255) DEFAULT NULL,
  `ap_threshold_mm` float DEFAULT '0',
  `ap_threshold_mm1` float DEFAULT '0',
  `ap_threshold_mm2` float DEFAULT '0',
  `ap_threshold_mm3` float DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `username` (`username`),
  UNIQUE KEY `email` (`email`),
  UNIQUE KEY `coin_address` (`coin_address`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 AUTO_INCREMENT=3 ;

-- --------------------------------------------------------

--
-- Table structure for table `blocks`
--

CREATE TABLE IF NOT EXISTS `blocks` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `height` int(10) unsigned NOT NULL,
  `blockhash` char(65) NOT NULL,
  `confirmations` int(10) NOT NULL,
  `amount` double NOT NULL,
  `difficulty` double NOT NULL,
  `time` int(11) NOT NULL,
  `accounted` tinyint(1) NOT NULL DEFAULT '0',
  `account_id` int(255) unsigned DEFAULT NULL,
  `worker_name` varchar(50) DEFAULT 'unknown',
  `shares` int(255) unsigned DEFAULT NULL,
  `share_id` int(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `height` (`height`,`blockhash`),
  KEY `time` (`time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='Discovered blocks persisted from Litecoin Service' AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `blocks_mm`
--

CREATE TABLE IF NOT EXISTS `blocks_mm` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `height` int(10) unsigned NOT NULL,
  `blockhash` char(65) NOT NULL,
  `confirmations` int(10) NOT NULL,
  `amount` double NOT NULL,
  `difficulty` double NOT NULL,
  `time` int(11) NOT NULL,
  `accounted` tinyint(1) NOT NULL DEFAULT '0',
  `account_id` int(255) unsigned DEFAULT NULL,
  `worker_name` varchar(50) DEFAULT 'unknown',
  `shares` int(255) unsigned DEFAULT NULL,
  `share_id` int(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `height` (`height`,`blockhash`),
  KEY `time` (`time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='Discovered blocks persisted from Litecoin Service' AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `blocks_mm1`
--

CREATE TABLE IF NOT EXISTS `blocks_mm1` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `height` int(10) unsigned NOT NULL,
  `blockhash` char(65) NOT NULL,
  `confirmations` int(10) NOT NULL,
  `amount` double NOT NULL,
  `difficulty` double NOT NULL,
  `time` int(11) NOT NULL,
  `accounted` tinyint(1) NOT NULL DEFAULT '0',
  `account_id` int(255) unsigned DEFAULT NULL,
  `worker_name` varchar(50) DEFAULT 'unknown',
  `shares` int(255) unsigned DEFAULT NULL,
  `share_id` int(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `height` (`height`,`blockhash`),
  KEY `time` (`time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='Discovered blocks persisted from Litecoin Service' AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `blocks_mm2`
--

CREATE TABLE IF NOT EXISTS `blocks_mm2` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `height` int(10) unsigned NOT NULL,
  `blockhash` char(65) NOT NULL,
  `confirmations` int(10) NOT NULL,
  `amount` double NOT NULL,
  `difficulty` double NOT NULL,
  `time` int(11) NOT NULL,
  `accounted` tinyint(1) NOT NULL DEFAULT '0',
  `account_id` int(255) unsigned DEFAULT NULL,
  `worker_name` varchar(50) DEFAULT 'unknown',
  `shares` int(255) unsigned DEFAULT NULL,
  `share_id` int(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `height` (`height`,`blockhash`),
  KEY `time` (`time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='Discovered blocks persisted from Litecoin Service' AUTO_INCREMENT=1 ;

-- --------------------------------------------------------
--
-- Table structure for table `blocks_mm3`
--

CREATE TABLE IF NOT EXISTS `blocks_mm3` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `height` int(10) unsigned NOT NULL,
  `blockhash` char(65) NOT NULL,
  `confirmations` int(10) NOT NULL,
  `amount` double NOT NULL,
  `difficulty` double NOT NULL,
  `time` int(11) NOT NULL,
  `accounted` tinyint(1) NOT NULL DEFAULT '0',
  `account_id` int(255) unsigned DEFAULT NULL,
  `worker_name` varchar(50) DEFAULT 'unknown',
  `shares` int(255) unsigned DEFAULT NULL,
  `share_id` int(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `height` (`height`,`blockhash`),
  KEY `time` (`time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='Discovered blocks persisted from Litecoin Service' AUTO_INCREMENT=1 ;

-- --------------------------------------------------------
--
-- Table structure for table `invitations`
--

CREATE TABLE IF NOT EXISTS `invitations` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `account_id` int(11) unsigned NOT NULL,
  `email` varchar(50) NOT NULL,
  `token_id` int(11) NOT NULL,
  `is_activated` tinyint(1) NOT NULL DEFAULT '0',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `monitoring`
--

CREATE TABLE IF NOT EXISTS `monitoring` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(30) NOT NULL,
  `type` varchar(15) NOT NULL,
  `value` varchar(255) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 COMMENT='Monitoring events from cronjobs' AUTO_INCREMENT=1014586 ;

--
-- Table structure for table `news`
--

CREATE TABLE IF NOT EXISTS `news` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `account_id` int(10) unsigned NOT NULL,
  `header` varchar(255) NOT NULL,
  `content` text NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `active` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `notifications`
--

CREATE TABLE IF NOT EXISTS `notifications` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `type` varchar(25) NOT NULL,
  `data` varchar(255) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT '1',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `account_id` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `active` (`active`),
  KEY `data` (`data`),
  KEY `account_id` (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `notification_settings`
--

CREATE TABLE IF NOT EXISTS `notification_settings` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `type` varchar(15) NOT NULL,
  `account_id` int(11) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `account_id_type` (`account_id`,`type`),
  KEY `account_id` (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `payouts`
--

CREATE TABLE IF NOT EXISTS `payouts` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `account_id` (`account_id`,`completed`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `payouts_mm`
--

CREATE TABLE IF NOT EXISTS `payouts_mm` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `payouts_mm1`
--

CREATE TABLE IF NOT EXISTS `payouts_mm1` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `payouts_mm2`
--

CREATE TABLE IF NOT EXISTS `payouts_mm2` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------
--
-- Table structure for table `payouts_mm3`
--

CREATE TABLE IF NOT EXISTS `payouts_mm3` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------
--
-- Table structure for table `pool_worker`
--

CREATE TABLE IF NOT EXISTS `pool_worker` (
  `id` int(255) NOT NULL AUTO_INCREMENT,
  `account_id` int(255) NOT NULL,
  `username` char(50) DEFAULT NULL,
  `password` char(255) DEFAULT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `monitor` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `username` (`username`),
  KEY `account_id` (`account_id`),
  KEY `pool_worker_username` (`username`(10))
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 AUTO_INCREMENT=14 ;

-- --------------------------------------------------------

--
-- Table structure for table `settings`
--

CREATE TABLE IF NOT EXISTS `settings` (
  `name` varchar(255) NOT NULL,
  `value` text,
  PRIMARY KEY (`name`),
  UNIQUE KEY `setting` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Dumping data for table `settings`
--

INSERT INTO `settings` (`name`, `value`) VALUES
('accounts_confirm_email_disabled', '1'),
('acl_blockfinder_statistics', '0'),
('acl_block_statistics', '1'),
('acl_hide_news_author', '0'),
('acl_pool_statistics', '1'),
('acl_round_statistics', '0'),
('acl_uptime_statistics', '0'),
('DB_VERSION', '0.0.5'),
('disable_about', '1'),
('disable_api', '0'),
('disable_auto_payouts', '0'),
('disable_contactform', '1'),
('disable_contactform_guest', '1'),
('disable_dashboard', '0'),
('disable_dashboard_api', '0'),
('disable_donors', '0'),
('disable_invitations', '0'),
('disable_manual_payouts', '0'),
('disable_navbar', '0'),
('disable_navbar_api', '0'),
('disable_notifications', '0'),
('disable_payouts', '0'),
('disable_transactionsummary', '0'),
('last_accounted_block_id', '0'),
('last_accounted_block_id_mm', '0'),
('lock_registration', '1'),
('maintenance', '0'),
('monitoring_uptimerobot_api_keys', 'MONITOR_API_KEY|MONITOR_NAME,MONITOR_API_KEY|MONITOR_NAME,...'),
('notifications_disable_block', '0'),
('pps_last_share_id_mm', NULL),
('recaptcha_enabled', '0'),
('recaptcha_enabled_contactform', '0'),
('recaptcha_enabled_logins', '0'),
('recaptcha_enabled_registrations', '0'),
('recaptcha_private_key', 'YOUR_PRIVATE_KEY'),
('recaptcha_public_key', 'YOUR_PUBLIC_KEY'),
('statistics_ajax_data_interval', '180'),
('statistics_ajax_long_refresh_interval', '600'),
('statistics_ajax_refresh_interval', '60'),
('statistics_analytics_code', 'Code from Google Analytics'),
('statistics_analytics_enabled', '0'),
('statistics_block_count', '20'),
('statistics_network_hashrate_modifier', '0.000001'),
('statistics_personal_hashrate_modifier', '0.000001'),
('statistics_pool_hashrate_modifier', '0.000001'),
('statistics_show_block_average', '0'),
('system_error_email', 'BlueDragon747.Blakecoin@gmail.com'),
('system_motd', ''),
('wallet_cold_coins', '0'),
('website_blockexplorer_disabled', '0'),
('website_blockexplorer_url', 'http://blc.cryptocoinexplorer.com/block/'),
('website_chaininfo_disabled', '0'),
('website_chaininfo_url', 'http://blc.cryptocoinexplorer.com/'),
('website_email', 'test@example.com'),
('website_mobile_theme', 'mobile'),
('website_name', 'BlakeMerged EU4'),
('website_slogan', 'Resistance is Futile'),
('website_theme', 'mpos'),
('website_title', 'BlakeMerged EU4 - Mining Evolved'),
('website_transactionexplorer_disabled', '1'),
('website_transactionexplorer_url', 'http://blc.cryptocoinexplorer.com/tx/');

-- --------------------------------------------------------

--
-- Table structure for table `shares`
--

CREATE TABLE IF NOT EXISTS `shares` (
  `id` bigint(30) NOT NULL AUTO_INCREMENT,
  `rem_host` varchar(255) NOT NULL,
  `username` varchar(120) NOT NULL,
  `our_result` enum('Y','N') NOT NULL,
  `upstream_result` enum('Y','N') DEFAULT NULL,
  `reason` varchar(50) DEFAULT NULL,
  `solution` varchar(257) NOT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `time` (`time`),
  KEY `upstream_result` (`upstream_result`),
  KEY `our_result` (`our_result`),
  KEY `username` (`username`),
  KEY `shares_username` (`username`(10))
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `shares_archive`
--

CREATE TABLE IF NOT EXISTS `shares_archive` (
  `id` int(255) unsigned NOT NULL AUTO_INCREMENT,
  `share_id` int(255) unsigned NOT NULL,
  `username` varchar(120) NOT NULL,
  `our_result` enum('Y','N') DEFAULT NULL,
  `upstream_result` enum('Y','N') DEFAULT NULL,
  `block_id` int(10) unsigned NOT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `share_id` (`share_id`),
  KEY `time` (`time`),
  KEY `our_result` (`our_result`),
  KEY `username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='Archive shares for potential later debugging purposes' AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `shares_archive_mm`
--

CREATE TABLE IF NOT EXISTS `shares_archive_mm` (
  `id` int(255) unsigned NOT NULL AUTO_INCREMENT,
  `share_id` int(255) unsigned NOT NULL,
  `username` varchar(120) NOT NULL,
  `our_result` enum('Y','N') DEFAULT NULL,
  `upstream_result` enum('Y','N') DEFAULT NULL,
  `block_id` int(10) unsigned NOT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `share_id` (`share_id`),
  KEY `time` (`time`),
  KEY `our_result` (`our_result`),
  KEY `username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='Archive shares for potential later debugging purposes' AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `shares_archive_mm1`
--

CREATE TABLE IF NOT EXISTS `shares_archive_mm1` (
  `id` int(255) unsigned NOT NULL AUTO_INCREMENT,
  `share_id` int(255) unsigned NOT NULL,
  `username` varchar(120) NOT NULL,
  `our_result` enum('Y','N') DEFAULT NULL,
  `upstream_result` enum('Y','N') DEFAULT NULL,
  `block_id` int(10) unsigned NOT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `share_id` (`share_id`),
  KEY `time` (`time`),
  KEY `our_result` (`our_result`),
  KEY `username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='Archive shares for potential later debugging purposes' AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `shares_archive_mm2`
--

CREATE TABLE IF NOT EXISTS `shares_archive_mm2` (
  `id` int(255) unsigned NOT NULL AUTO_INCREMENT,
  `share_id` int(255) unsigned NOT NULL,
  `username` varchar(120) NOT NULL,
  `our_result` enum('Y','N') DEFAULT NULL,
  `upstream_result` enum('Y','N') DEFAULT NULL,
  `block_id` int(10) unsigned NOT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `share_id` (`share_id`),
  KEY `time` (`time`),
  KEY `our_result` (`our_result`),
  KEY `username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='Archive shares for potential later debugging purposes' AUTO_INCREMENT=1 ;

-- --------------------------------------------------------
--
-- Table structure for table `shares_archive_mm3`
--

CREATE TABLE IF NOT EXISTS `shares_archive_mm3` (
  `id` int(255) unsigned NOT NULL AUTO_INCREMENT,
  `share_id` int(255) unsigned NOT NULL,
  `username` varchar(120) NOT NULL,
  `our_result` enum('Y','N') DEFAULT NULL,
  `upstream_result` enum('Y','N') DEFAULT NULL,
  `block_id` int(10) unsigned NOT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `share_id` (`share_id`),
  KEY `time` (`time`),
  KEY `our_result` (`our_result`),
  KEY `username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='Archive shares for potential later debugging purposes' AUTO_INCREMENT=1 ;

-- --------------------------------------------------------
--
-- Table structure for table `shares_mm`
--

CREATE TABLE IF NOT EXISTS `shares_mm` (
  `id` bigint(30) NOT NULL AUTO_INCREMENT,
  `rem_host` varchar(255) NOT NULL,
  `username` varchar(120) NOT NULL,
  `our_result` enum('Y','N') NOT NULL,
  `upstream_result` enum('Y','N') DEFAULT NULL,
  `reason` varchar(50) DEFAULT NULL,
  `solution` varchar(257) NOT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `time` (`time`),
  KEY `upstream_result` (`upstream_result`),
  KEY `our_result` (`our_result`),
  KEY `username` (`username`),
  KEY `shares_username` (`username`(10))
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `shares_mm1`
--

CREATE TABLE IF NOT EXISTS `shares_mm1` (
  `id` bigint(30) NOT NULL AUTO_INCREMENT,
  `rem_host` varchar(255) NOT NULL,
  `username` varchar(120) NOT NULL,
  `our_result` enum('Y','N') NOT NULL,
  `upstream_result` enum('Y','N') DEFAULT NULL,
  `reason` varchar(50) DEFAULT NULL,
  `solution` varchar(257) NOT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `time` (`time`),
  KEY `upstream_result` (`upstream_result`),
  KEY `our_result` (`our_result`),
  KEY `username` (`username`),
  KEY `shares_username` (`username`(10))
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `shares_mm2`
--

CREATE TABLE IF NOT EXISTS `shares_mm2` (
  `id` bigint(30) NOT NULL AUTO_INCREMENT,
  `rem_host` varchar(255) NOT NULL,
  `username` varchar(120) NOT NULL,
  `our_result` enum('Y','N') NOT NULL,
  `upstream_result` enum('Y','N') DEFAULT NULL,
  `reason` varchar(50) DEFAULT NULL,
  `solution` varchar(257) NOT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `time` (`time`),
  KEY `upstream_result` (`upstream_result`),
  KEY `our_result` (`our_result`),
  KEY `username` (`username`),
  KEY `shares_username` (`username`(10))
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------
--
-- Table structure for table `shares_mm3`
--

CREATE TABLE IF NOT EXISTS `shares_mm3` (
  `id` bigint(30) NOT NULL AUTO_INCREMENT,
  `rem_host` varchar(255) NOT NULL,
  `username` varchar(120) NOT NULL,
  `our_result` enum('Y','N') NOT NULL,
  `upstream_result` enum('Y','N') DEFAULT NULL,
  `reason` varchar(50) DEFAULT NULL,
  `solution` varchar(257) NOT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `time` (`time`),
  KEY `upstream_result` (`upstream_result`),
  KEY `our_result` (`our_result`),
  KEY `username` (`username`),
  KEY `shares_username` (`username`(10))
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------
--
-- Table structure for table `statistics_shares`
--

CREATE TABLE IF NOT EXISTS `statistics_shares` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `account_id` int(10) unsigned NOT NULL,
  `block_id` int(10) unsigned NOT NULL,
  `valid` int(11) NOT NULL,
  `invalid` int(11) NOT NULL DEFAULT '0',
  `pplns_valid` int(11) NOT NULL,
  `pplns_invalid` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `account_id` (`account_id`),
  KEY `block_id` (`block_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `templates`
--

CREATE TABLE IF NOT EXISTS `templates` (
  `template` varchar(255) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT '0',
  `content` mediumtext,
  `modified_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`template`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- --------------------------------------------------------

--
-- Table structure for table `tokens`
--

CREATE TABLE IF NOT EXISTS `tokens` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `token` varchar(65) NOT NULL,
  `type` tinyint(4) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `token` (`token`),
  KEY `account_id` (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `token_types`
--

CREATE TABLE IF NOT EXISTS `token_types` (
  `id` tinyint(4) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(25) NOT NULL,
  `expiration` int(11) DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 AUTO_INCREMENT=8 ;

--
-- Dumping data for table `token_types`
--

INSERT INTO `token_types` (`id`, `name`, `expiration`) VALUES
(1, 'password_reset', 3600),
(2, 'confirm_email', 0),
(3, 'invitation', 0),
(4, 'account_unlock', 0),
(5, 'account_edit', 3600),
(6, 'change_pw', 3600),
(7, 'withdraw_funds', 3600);

-- --------------------------------------------------------

--
-- Table structure for table `transactions`
--

CREATE TABLE IF NOT EXISTS `transactions` (
  `id` int(255) NOT NULL AUTO_INCREMENT,
  `account_id` int(255) unsigned NOT NULL,
  `type` varchar(25) DEFAULT NULL,
  `coin_address` varchar(255) DEFAULT NULL,
  `amount` double DEFAULT '0',
  `block_id` int(255) DEFAULT NULL,
  `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `txid` varchar(256) DEFAULT NULL,
  `archived` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `block_id` (`block_id`),
  KEY `account_id` (`account_id`),
  KEY `type` (`type`),
  KEY `archived` (`archived`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `transactions_mm`
--

CREATE TABLE IF NOT EXISTS `transactions_mm` (
  `id` int(255) NOT NULL AUTO_INCREMENT,
  `account_id` int(255) unsigned NOT NULL,
  `type` varchar(25) DEFAULT NULL,
  `coin_address` varchar(255) DEFAULT NULL,
  `amount` double DEFAULT '0',
  `block_id` int(255) DEFAULT NULL,
  `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `txid` varchar(256) DEFAULT NULL,
  `archived` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `block_id` (`block_id`),
  KEY `account_id` (`account_id`),
  KEY `type` (`type`),
  KEY `archived` (`archived`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `transactions_mm1`
--

CREATE TABLE IF NOT EXISTS `transactions_mm1` (
  `id` int(255) NOT NULL AUTO_INCREMENT,
  `account_id` int(255) unsigned NOT NULL,
  `type` varchar(25) DEFAULT NULL,
  `coin_address` varchar(255) DEFAULT NULL,
  `amount` double DEFAULT '0',
  `block_id` int(255) DEFAULT NULL,
  `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `txid` varchar(256) DEFAULT NULL,
  `archived` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `block_id` (`block_id`),
  KEY `account_id` (`account_id`),
  KEY `type` (`type`),
  KEY `archived` (`archived`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

--
-- Table structure for table `transactions_mm2`
--

CREATE TABLE IF NOT EXISTS `transactions_mm2` (
  `id` int(255) NOT NULL AUTO_INCREMENT,
  `account_id` int(255) unsigned NOT NULL,
  `type` varchar(25) DEFAULT NULL,
  `coin_address` varchar(255) DEFAULT NULL,
  `amount` double DEFAULT '0',
  `block_id` int(255) DEFAULT NULL,
  `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `txid` varchar(256) DEFAULT NULL,
  `archived` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `block_id` (`block_id`),
  KEY `account_id` (`account_id`),
  KEY `type` (`type`),
  KEY `archived` (`archived`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------
--
-- Table structure for table `transactions_mm3`
--

CREATE TABLE IF NOT EXISTS `transactions_mm3` (
  `id` int(255) NOT NULL AUTO_INCREMENT,
  `account_id` int(255) unsigned NOT NULL,
  `type` varchar(25) DEFAULT NULL,
  `coin_address` varchar(255) DEFAULT NULL,
  `amount` double DEFAULT '0',
  `block_id` int(255) DEFAULT NULL,
  `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `txid` varchar(256) DEFAULT NULL,
  `archived` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `block_id` (`block_id`),
  KEY `account_id` (`account_id`),
  KEY `type` (`type`),
  KEY `archived` (`archived`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

-- --------------------------------------------------------

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
