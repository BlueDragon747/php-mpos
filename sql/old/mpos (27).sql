-- phpMyAdmin SQL Dump
-- version 4.1.14
-- http://www.phpmyadmin.net
--
-- Host: localhost
-- Generation Time: May 11, 2014 at 06:35 PM
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
  `ap_threshold_mm` float DEFAULT '0',
  `coin_address_mm1` varchar(255) DEFAULT NULL,
  `ap_threshold_mm1` float DEFAULT '0',
  `coin_address_mm2` varchar(255) DEFAULT NULL,
  `ap_threshold_mm2` float DEFAULT '0',
  `coin_address_mm3` varchar(255) DEFAULT NULL,
  `ap_threshold_mm3` float DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `username` (`username`),
  UNIQUE KEY `email` (`email`),
  UNIQUE KEY `coin_address` (`coin_address`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 AUTO_INCREMENT=4 ;

--
-- Dumping data for table `accounts`
--

INSERT INTO `accounts` (`id`, `is_admin`, `is_anonymous`, `no_fees`, `username`, `pass`, `email`, `notify_email`, `loggedIp`, `is_locked`, `failed_logins`, `failed_pins`, `signup_timestamp`, `last_login`, `pin`, `api_key`, `token`, `donate_percent`, `ap_threshold`, `coin_address`, `coin_address_mm`, `ap_threshold_mm`, `coin_address_mm1`, `ap_threshold_mm1`, `coin_address_mm2`, `ap_threshold_mm2`, `coin_address_mm3`, `ap_threshold_mm3`) VALUES
(1, 1, 0, 0, 'BlueDragon747', 'aa62ee7bc5fc2ccbb108d14ebf851a0262805c4f8e1032686a39f022eaf622cb', 'bluedragon747.blakecoin@gmail.com', NULL, '151.231.43.180', 0, 0, 1, 1399817512, 1399828860, '25fada0cb99e8ade9c6d3f04dd50fe1751d28ca373b5117a9278f26cb442d2e3', '58ed85f2ed2f176e613c239bf6a23971a956677eafab03809dadffc15e6cfe79', NULL, 0, 5, 'BqJbf6XXKDR17iGJGqoH1MimyL29a3hGpY', 'Bahf4PguLjtnRibR9ZY8FQCtvHPDBjFKXj', 5, '9nbayFagkxgPMAEdoKZsAYGtxFmNHJgsVK', 5, '9nbayFagkxgPMAEdoKZsAYGtxFmNHJgsVK', 5, '9nbayFagkxgPMAEdoKZsAYGtxFmNHJgsVK', 5);

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
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 COMMENT='Monitoring events from cronjobs' AUTO_INCREMENT=1034753 ;

--
-- Dumping data for table `monitoring`
--

INSERT INTO `monitoring` (`id`, `name`, `type`, `value`) VALUES
(1014586, 'payouts_disabled', 'yesno', '0'),
(1014587, 'payouts_mm_disabled', 'yesno', '0'),
(1014588, 'payouts_mm_starttime', 'date', '1399833303'),
(1014589, 'payouts_mm_active', 'yesno', '0'),
(1014590, 'payouts_mm_message', 'message', 'OK'),
(1014591, 'payouts_mm_status', 'okerror', '0'),
(1014592, 'payouts_mm_endtime', 'date', '1399833303'),
(1014594, 'payouts_mm1_disabled', 'yesno', '0'),
(1014595, 'payouts_mm1_starttime', 'date', '1399833303'),
(1014596, 'payouts_mm1_active', 'yesno', '0'),
(1014597, 'payouts_mm1_message', 'message', 'OK'),
(1014598, 'payouts_mm1_status', 'okerror', '0'),
(1014599, 'payouts_mm1_endtime', 'date', '1399833303'),
(1014601, 'notifications_disabled', 'yesno', '0'),
(1014602, 'notifications_starttime', 'date', '1399833303'),
(1014603, 'notifications_active', 'yesno', '0'),
(1014604, 'notifications_message', 'message', 'OK'),
(1014605, 'notifications_status', 'okerror', '0'),
(1014606, 'notifications_endtime', 'date', '1399833303'),
(1014607, 'notifications_runtime', 'time', '0.0045318603515625'),
(1014609, 'statistics_disabled', 'yesno', '0'),
(1014610, 'statistics_starttime', 'date', '1399833303'),
(1014611, 'statistics_active', 'yesno', '0'),
(1014612, 'statistics_message', 'message', 'OK'),
(1014613, 'statistics_status', 'okerror', '0'),
(1014614, 'statistics_endtime', 'date', '1399833303'),
(1014615, 'statistics_runtime', 'time', '0.0088729858398438'),
(1014617, 'token_cleanup_disabled', 'yesno', '0'),
(1014618, 'token_cleanup_starttime', 'date', '1399833303'),
(1014619, 'token_cleanup_active', 'yesno', '0'),
(1014620, 'token_cleanup_message', 'message', 'OK'),
(1014621, 'token_cleanup_status', 'okerror', '0'),
(1014622, 'token_cleanup_endtime', 'date', '1399833303'),
(1014623, 'token_cleanup_runtime', 'time', '0.0055279731750488'),
(1014625, 'archive_cleanup_disabled', 'yesno', '0'),
(1014626, 'archive_cleanup_starttime', 'date', '1399833303'),
(1014627, 'archive_cleanup_active', 'yesno', '0'),
(1014628, 'archive_cleanup_message', 'message', 'OK'),
(1014629, 'archive_cleanup_status', 'okerror', '0'),
(1014630, 'archive_cleanup_endtime', 'date', '1399833303'),
(1014631, 'archive_cleanup_runtime', 'time', '0.0054519176483154'),
(1014633, 'archive_cleanup_mm_disabled', 'yesno', '0'),
(1014634, 'archive_cleanup_mm_starttime', 'date', '1399833303'),
(1014635, 'archive_cleanup_mm_active', 'yesno', '0'),
(1014636, 'archive_cleanup_mm_message', 'message', 'OK'),
(1014637, 'archive_cleanup_mm_status', 'okerror', '0'),
(1014638, 'archive_cleanup_mm_endtime', 'date', '1399833303'),
(1014639, 'archive_cleanup_mm_runtime', 'time', '0.004734992980957'),
(1014641, 'archive_cleanup_mm1_disabled', 'yesno', '0'),
(1014642, 'archive_cleanup_mm1_starttime', 'date', '1399833303'),
(1014643, 'archive_cleanup_mm1_active', 'yesno', '0'),
(1014644, 'archive_cleanup_mm1_message', 'message', 'OK'),
(1014645, 'archive_cleanup_mm1_status', 'okerror', '0'),
(1014646, 'archive_cleanup_mm1_endtime', 'date', '1399833303'),
(1014647, 'archive_cleanup_mm1_runtime', 'time', '0.0051620006561279'),
(1014649, 'liquid_payout_disabled', 'yesno', '0'),
(1014650, 'liquid_payout_starttime', 'date', '1399833303'),
(1014651, 'liquid_payout_active', 'yesno', '0'),
(1014652, 'liquid_payout_message', 'message', 'No coins in wallet available'),
(1014653, 'liquid_payout_status', 'okerror', '0'),
(1014654, 'liquid_payout_endtime', 'date', '1399833303'),
(1014656, 'findblock_disabled', 'yesno', '0'),
(1014657, 'findblock_starttime', 'date', '1399833302'),
(1014658, 'findblock_active', 'yesno', '0'),
(1014659, 'findblock_message', 'message', 'OK'),
(1014660, 'findblock_status', 'okerror', '0'),
(1014661, 'findblock_endtime', 'date', '1399833302'),
(1014663, 'findblock_mm_disabled', 'yesno', '0'),
(1014664, 'findblock_mm_starttime', 'date', '1399833302'),
(1014665, 'findblock_mm_active', 'yesno', '0'),
(1014666, 'findblock_mm_message', 'message', 'OK'),
(1014667, 'findblock_mm_status', 'okerror', '0'),
(1014668, 'findblock_mm_endtime', 'date', '1399833302'),
(1014670, 'findblock_mm1_disabled', 'yesno', '0'),
(1014671, 'findblock_mm1_starttime', 'date', '1399833302'),
(1014672, 'findblock_mm1_active', 'yesno', '0'),
(1014673, 'findblock_mm1_message', 'message', 'OK'),
(1014674, 'findblock_mm1_status', 'okerror', '0'),
(1014675, 'findblock_mm1_endtime', 'date', '1399833302'),
(1014677, 'pplns_payout_disabled', 'yesno', '0'),
(1014678, 'pplns_payout_starttime', 'date', '1399833302'),
(1014679, 'pplns_payout_active', 'yesno', '0'),
(1014680, 'pplns_payout_message', 'message', 'No new unaccounted blocks'),
(1014681, 'pplns_payout_status', 'okerror', '0'),
(1014682, 'pplns_payout_endtime', 'date', '1399833302'),
(1014683, 'pplns_payout_mm_disabled', 'yesno', '0'),
(1014684, 'pplns_payout_mm_starttime', 'date', '1399833302'),
(1014685, 'pplns_payout_mm_active', 'yesno', '0'),
(1014686, 'pplns_payout_mm_message', 'message', 'No new unaccounted blocks'),
(1014687, 'pplns_payout_mm_status', 'okerror', '0'),
(1014688, 'pplns_payout_mm_endtime', 'date', '1399833302'),
(1014689, 'pplns_payout_mm1_disabled', 'yesno', '0'),
(1014690, 'pplns_payout_mm1_starttime', 'date', '1399833302'),
(1014691, 'pplns_payout_mm1_active', 'yesno', '0'),
(1014692, 'pplns_payout_mm1_message', 'message', 'No new unaccounted blocks'),
(1014693, 'pplns_payout_mm1_status', 'okerror', '0'),
(1014694, 'pplns_payout_mm1_endtime', 'date', '1399833302'),
(1014695, 'blockupdate_disabled', 'yesno', '0'),
(1014696, 'blockupdate_starttime', 'date', '1399833302'),
(1014697, 'blockupdate_active', 'yesno', '0'),
(1014698, 'blockupdate_message', 'message', 'OK'),
(1014699, 'blockupdate_status', 'okerror', '0'),
(1014700, 'blockupdate_endtime', 'date', '1399833302'),
(1014702, 'blockupdate_mm_disabled', 'yesno', '0'),
(1014703, 'blockupdate_mm_starttime', 'date', '1399833302'),
(1014704, 'blockupdate_mm_active', 'yesno', '0'),
(1014705, 'blockupdate_mm_message', 'message', 'OK'),
(1014706, 'blockupdate_mm_status', 'okerror', '0'),
(1014707, 'blockupdate_mm_endtime', 'date', '1399833302'),
(1014810, 'blockupdate_mm1_disabled', 'yesno', '0'),
(1014811, 'blockupdate_mm1_starttime', 'date', '1399833303'),
(1014812, 'blockupdate_mm1_active', 'yesno', '0'),
(1014813, 'blockupdate_mm1_message', 'message', 'OK'),
(1014814, 'blockupdate_mm1_status', 'okerror', '0'),
(1014815, 'blockupdate_mm1_endtime', 'date', '1399833303'),
(1014818, 'payouts_starttime', 'date', '1399833303'),
(1014819, 'payouts_active', 'yesno', '0'),
(1014820, 'payouts_message', 'message', 'OK'),
(1014821, 'payouts_status', 'okerror', '0'),
(1014822, 'payouts_endtime', 'date', '1399833303'),
(1015890, 'blockupdate_runtime', 'time', '0.0060160160064697'),
(1015898, 'blockupdate_mm_runtime', 'time', '0.0067131519317627'),
(1015913, 'payouts_runtime', 'time', '0.010006904602051'),
(1015921, 'payouts_mm_runtime', 'time', '0.0091438293457031'),
(1015990, 'findblock_runtime', 'time', '0.024154901504517'),
(1015998, 'findblock_mm_runtime', 'time', '0.01634693145752'),
(1017175, 'blockupdate_mm1_runtime', 'time', '0.005903959274292'),
(1017199, 'payouts_mm1_runtime', 'time', '0.008760929107666'),
(1017277, 'findblock_mm1_runtime', 'time', '0.0092620849609375');

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
('lock_registration', '0'),
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

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
