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
-- Dumping data for table `monitoring`
--

INSERT INTO `monitoring` (`id`, `name`, `type`, `value`) VALUES
(972006, 'findblock_starttime', 'date', '1399694161'),
(972007, 'findblock_active', 'yesno', '0'),
(972008, 'findblock_message', 'message', 'Cron disbaled due to errors'),
(972009, 'findblock_status', 'okerror', '1'),
(972010, 'findblock_endtime', 'date', '1399718761'),
(972011, 'findblock_mm_starttime', 'date', '1399694222'),
(972012, 'findblock_mm_active', 'yesno', '0'),
(972013, 'findblock_mm_message', 'message', 'Cron disbaled due to errors'),
(972014, 'findblock_mm_status', 'okerror', '1'),
(972015, 'findblock_mm_endtime', 'date', '1399718761'),
(972016, 'pplns_payout_starttime', 'date', '1399718761'),
(972017, 'pplns_payout_active', 'yesno', '0'),
(972018, 'pplns_payout_message', 'message', 'No new unaccounted blocks'),
(972019, 'pplns_payout_status', 'okerror', '0'),
(972020, 'pplns_payout_endtime', 'date', '1399718761'),
(972021, 'pplns_payout_mm_starttime', 'date', '1399718761'),
(972022, 'pplns_payout_mm_active', 'yesno', '0'),
(972023, 'pplns_payout_mm_message', 'message', 'No new unaccounted blocks'),
(972024, 'pplns_payout_mm_status', 'okerror', '0'),
(972025, 'pplns_payout_mm_endtime', 'date', '1399718761'),
(972026, 'blockupdate_starttime', 'date', '1399694282'),
(972027, 'blockupdate_active', 'yesno', '0'),
(972028, 'blockupdate_message', 'message', 'Cron disbaled due to errors'),
(972029, 'blockupdate_status', 'okerror', '1'),
(972030, 'blockupdate_endtime', 'date', '1399718761'),
(972031, 'blockupdate_mm_starttime', 'date', '1399694342'),
(972032, 'blockupdate_mm_active', 'yesno', '0'),
(972033, 'blockupdate_mm_message', 'message', 'Cron disbaled due to errors'),
(972034, 'blockupdate_mm_status', 'okerror', '1'),
(972035, 'blockupdate_mm_endtime', 'date', '1399718762'),
(972036, 'payouts_starttime', 'date', '1399694403'),
(972037, 'payouts_active', 'yesno', '0'),
(972038, 'payouts_message', 'message', 'Cron disbaled due to errors'),
(972039, 'payouts_status', 'okerror', '1'),
(972040, 'payouts_endtime', 'date', '1399718762'),
(972041, 'payouts_mm_starttime', 'date', '1399694463'),
(972042, 'payouts_mm_active', 'yesno', '0'),
(972043, 'payouts_mm_message', 'message', 'Cron disbaled due to errors'),
(972044, 'payouts_mm_status', 'okerror', '1'),
(972045, 'payouts_mm_endtime', 'date', '1399718762'),
(972046, 'notifications_starttime', 'date', '1399718762'),
(972047, 'notifications_active', 'yesno', '0'),
(972048, 'notifications_message', 'message', 'OK'),
(972049, 'notifications_status', 'okerror', '0'),
(972050, 'notifications_endtime', 'date', '1399718762'),
(972051, 'statistics_starttime', 'date', '1399718762'),
(972052, 'statistics_active', 'yesno', '0'),
(972053, 'statistics_message', 'message', 'OK'),
(972054, 'statistics_status', 'okerror', '0'),
(972055, 'statistics_endtime', 'date', '1399718762'),
(972056, 'token_cleanup_starttime', 'date', '1399718762'),
(972057, 'token_cleanup_active', 'yesno', '0'),
(972058, 'token_cleanup_message', 'message', 'OK'),
(972059, 'token_cleanup_status', 'okerror', '0'),
(972060, 'token_cleanup_endtime', 'date', '1399718762'),
(972061, 'archive_cleanup_starttime', 'date', '1399718762'),
(972062, 'archive_cleanup_active', 'yesno', '0'),
(972063, 'archive_cleanup_message', 'message', 'OK'),
(972064, 'archive_cleanup_status', 'okerror', '0'),
(972065, 'archive_cleanup_endtime', 'date', '1399718762'),
(972066, 'archive_cleanup_mm_starttime', 'date', '1399718762'),
(972067, 'archive_cleanup_mm_active', 'yesno', '0'),
(972068, 'archive_cleanup_mm_message', 'message', 'OK'),
(972069, 'archive_cleanup_mm_status', 'okerror', '0'),
(972070, 'archive_cleanup_mm_endtime', 'date', '1399718762'),
(972071, 'liquid_payout_starttime', 'date', '1399694524'),
(972072, 'liquid_payout_active', 'yesno', '0'),
(972073, 'liquid_payout_message', 'message', 'Cron disbaled due to errors'),
(972074, 'liquid_payout_status', 'okerror', '1'),
(972075, 'liquid_payout_endtime', 'date', '1399718763'),
(972086, 'findblock_mm1_starttime', 'date', '1399714861'),
(972087, 'findblock_mm1_active', 'yesno', '0'),
(972088, 'findblock_mm1_message', 'message', 'Cron disbaled due to errors'),
(972089, 'findblock_mm1_status', 'okerror', '1'),
(972090, 'findblock_mm1_endtime', 'date', '1399718761'),
(972091, 'findblock_mm2_starttime', 'date', '1399714922'),
(972092, 'findblock_mm2_active', 'yesno', '0'),
(972093, 'findblock_mm2_message', 'message', 'Cron disbaled due to errors'),
(972094, 'findblock_mm2_status', 'okerror', '1'),
(972095, 'findblock_mm2_endtime', 'date', '1399718761'),
(972106, 'pplns_payout_mm1_starttime', 'date', '1399718761'),
(972107, 'pplns_payout_mm1_active', 'yesno', '0'),
(972108, 'pplns_payout_mm1_message', 'message', 'No new unaccounted blocks'),
(972109, 'pplns_payout_mm1_status', 'okerror', '0'),
(972110, 'pplns_payout_mm1_endtime', 'date', '1399718761'),
(972111, 'pplns_payout_mm2_starttime', 'date', '1399718761'),
(972112, 'pplns_payout_mm2_active', 'yesno', '0'),
(972113, 'pplns_payout_mm2_message', 'message', 'No new unaccounted blocks'),
(972114, 'pplns_payout_mm2_status', 'okerror', '0'),
(972115, 'pplns_payout_mm2_endtime', 'date', '1399718761'),
(972126, 'blockupdate_mm1_starttime', 'date', '1399714982'),
(972127, 'blockupdate_mm1_active', 'yesno', '0'),
(972128, 'blockupdate_mm1_message', 'message', 'Cron disbaled due to errors'),
(972129, 'blockupdate_mm1_status', 'okerror', '1'),
(972130, 'blockupdate_mm1_endtime', 'date', '1399718762'),
(972131, 'blockupdate_mm2_starttime', 'date', '1399715042'),
(972132, 'blockupdate_mm2_active', 'yesno', '0'),
(972133, 'blockupdate_mm2_message', 'message', 'Cron disbaled due to errors'),
(972134, 'blockupdate_mm2_status', 'okerror', '1'),
(972135, 'blockupdate_mm2_endtime', 'date', '1399718762'),
(972146, 'payouts_mm1_starttime', 'date', '1399715103'),
(972147, 'payouts_mm1_active', 'yesno', '0'),
(972148, 'payouts_mm1_message', 'message', 'Cron disbaled due to errors'),
(972149, 'payouts_mm1_status', 'okerror', '1'),
(972150, 'payouts_mm1_endtime', 'date', '1399718762'),
(972151, 'payouts_mm2_starttime', 'date', '1399715163'),
(972152, 'payouts_mm2_active', 'yesno', '0'),
(972153, 'payouts_mm2_message', 'message', 'Cron disbaled due to errors'),
(972154, 'payouts_mm2_status', 'okerror', '1'),
(972155, 'payouts_mm2_endtime', 'date', '1399718762'),
(972181, 'archive_cleanup_mm1_starttime', 'date', '1399718762'),
(972182, 'archive_cleanup_mm1_active', 'yesno', '0'),
(972183, 'archive_cleanup_mm1_message', 'message', 'OK'),
(972184, 'archive_cleanup_mm1_status', 'okerror', '0'),
(972185, 'archive_cleanup_mm1_endtime', 'date', '1399718762'),
(972186, 'archive_cleanup_mm2_starttime', 'date', '1399718763'),
(972187, 'archive_cleanup_mm2_active', 'yesno', '0'),
(972188, 'archive_cleanup_mm2_message', 'message', 'OK'),
(972189, 'archive_cleanup_mm2_status', 'okerror', '0'),
(972190, 'archive_cleanup_mm2_endtime', 'date', '1399718763'),
(974021, 'findblock_disabled', 'yesno', '1'),
(974027, 'findblock_mm_disabled', 'yesno', '1'),
(974047, 'blockupdate_disabled', 'yesno', '1'),
(974053, 'blockupdate_mm_disabled', 'yesno', '1'),
(974061, 'payouts_disabled', 'yesno', '1'),
(974067, 'payouts_mm_disabled', 'yesno', '1'),
(974075, 'notifications_runtime', 'time', '0.0058290958404541'),
(974082, 'statistics_runtime', 'time', '0.0096170902252197'),
(974089, 'token_cleanup_runtime', 'time', '0.010894060134888'),
(974096, 'archive_cleanup_runtime', 'time', '0.0062918663024902'),
(974103, 'archive_cleanup_mm_runtime', 'time', '0.0056371688842773'),
(974110, 'archive_cleanup_mm1_runtime', 'time', '0.0081868171691895'),
(974117, 'archive_cleanup_mm2_runtime', 'time', '0.0062899589538574'),
(974124, 'liquid_payout_disabled', 'yesno', '1'),
(1006555, 'findblock_mm1_disabled', 'yesno', '1'),
(1006561, 'findblock_mm2_disabled', 'yesno', '1'),
(1006597, 'blockupdate_mm1_disabled', 'yesno', '1'),
(1006603, 'blockupdate_mm2_disabled', 'yesno', '1'),
(1006619, 'payouts_mm1_disabled', 'yesno', '1'),
(1006625, 'payouts_mm2_disabled', 'yesno', '1');

-- --------------------------------------------------------

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
