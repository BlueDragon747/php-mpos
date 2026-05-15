-- --------------------------------------------------------
-- Host:                         127.0.0.1
-- Server version:               5.7.37-0ubuntu0.18.04.1 - (Ubuntu)
-- Server OS:                    Linux
-- HeidiSQL Version:             12.16.0.7229
-- --------------------------------------------------------

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET NAMES utf8 */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;


-- Dumping database structure for mpos
CREATE DATABASE IF NOT EXISTS `mpos` /*!40100 DEFAULT CHARACTER SET latin1 */;
USE `mpos`;

-- Dumping structure for table mpos.accounts
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
  `coin_address_mm4` varchar(255) DEFAULT NULL,
  `ap_threshold_mm4` float DEFAULT '0',
  `coin_address_mm5` varchar(255) DEFAULT '',
  `ap_threshold_mm5` float DEFAULT '0',
  `coin_address_mm6` varchar(255) DEFAULT '',
  `ap_threshold_mm6` float DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `username` (`username`),
  UNIQUE KEY `email` (`email`),
  KEY `coin_address` (`coin_address`) USING BTREE,
  KEY `coin_address_mm` (`coin_address_mm`) USING BTREE,
  KEY `coin_address_mm1` (`coin_address_mm1`,`coin_address_mm2`,`coin_address_mm3`) USING BTREE
) ENGINE=InnoDB AUTO_INCREMENT=5013 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.blocks
CREATE TABLE IF NOT EXISTS `blocks` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `height` int(10) unsigned NOT NULL,
  `blockhash` char(65) NOT NULL,
  `confirmations` int(10) NOT NULL,
  `amount` double NOT NULL,
  `difficulty` double NOT NULL,
  `time` int(11) NOT NULL,
  `accounted` tinyint(1) NOT NULL DEFAULT '0',
  `account_id` int(255) unsigned DEFAULT '1',
  `worker_name` varchar(50) DEFAULT 'BlueDragon747.1',
  `shares` int(255) unsigned DEFAULT NULL,
  `share_id` int(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `height` (`height`,`blockhash`),
  KEY `time` (`time`)
) ENGINE=InnoDB AUTO_INCREMENT=913340 DEFAULT CHARSET=utf8 COMMENT='Discovered blocks persisted from Litecoin Service';

-- Data exporting was unselected.

-- Dumping structure for table mpos.blocks_mm
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
) ENGINE=InnoDB AUTO_INCREMENT=1009104 DEFAULT CHARSET=utf8 COMMENT='Discovered blocks persisted from Litecoin Service';

-- Data exporting was unselected.

-- Dumping structure for table mpos.blocks_mm1
CREATE TABLE IF NOT EXISTS `blocks_mm1` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `height` int(10) unsigned NOT NULL,
  `blockhash` char(65) NOT NULL,
  `confirmations` int(10) NOT NULL,
  `amount` double NOT NULL,
  `difficulty` double NOT NULL,
  `time` int(11) NOT NULL,
  `accounted` tinyint(1) NOT NULL DEFAULT '0',
  `account_id` int(255) unsigned DEFAULT '1',
  `worker_name` varchar(50) DEFAULT 'BlueDragon747.1',
  `shares` int(255) unsigned DEFAULT NULL,
  `share_id` int(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `height` (`height`,`blockhash`),
  KEY `time` (`time`)
) ENGINE=InnoDB AUTO_INCREMENT=1205384 DEFAULT CHARSET=utf8 COMMENT='Discovered blocks persisted from Litecoin Service';

-- Data exporting was unselected.

-- Dumping structure for table mpos.blocks_mm2
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='Discovered blocks persisted from Litecoin Service';

-- Data exporting was unselected.

-- Dumping structure for table mpos.blocks_mm3
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
  `shares` int(255) unsigned DEFAULT '1',
  `share_id` bigint(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `height` (`height`,`blockhash`),
  KEY `time` (`time`)
) ENGINE=InnoDB AUTO_INCREMENT=2861649 DEFAULT CHARSET=utf8 COMMENT='Discovered blocks persisted from Litecoin Service';

-- Data exporting was unselected.

-- Dumping structure for table mpos.blocks_mm4
CREATE TABLE IF NOT EXISTS `blocks_mm4` (
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
) ENGINE=InnoDB AUTO_INCREMENT=2067162 DEFAULT CHARSET=utf8 COMMENT='Discovered blocks persisted from Litecoin Service';

-- Data exporting was unselected.

-- Dumping structure for table mpos.blocks_mm5
CREATE TABLE IF NOT EXISTS `blocks_mm5` (
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
) ENGINE=InnoDB AUTO_INCREMENT=954799 DEFAULT CHARSET=utf8 COMMENT='Discovered blocks persisted from Litecoin Service';

-- Data exporting was unselected.

-- Dumping structure for table mpos.blocks_mm6
CREATE TABLE IF NOT EXISTS `blocks_mm6` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='Discovered blocks persisted from Litecoin Service';

-- Data exporting was unselected.

-- Dumping structure for table mpos.invitations
CREATE TABLE IF NOT EXISTS `invitations` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `account_id` int(11) unsigned NOT NULL,
  `email` varchar(50) NOT NULL,
  `token_id` int(11) NOT NULL,
  `is_activated` tinyint(1) NOT NULL DEFAULT '0',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.monitoring
CREATE TABLE IF NOT EXISTS `monitoring` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(30) NOT NULL,
  `type` varchar(15) NOT NULL,
  `value` varchar(255) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB AUTO_INCREMENT=8047727 DEFAULT CHARSET=utf8 COMMENT='Monitoring events from cronjobs';

-- Data exporting was unselected.

-- Dumping structure for table mpos.news
CREATE TABLE IF NOT EXISTS `news` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `account_id` int(10) unsigned NOT NULL,
  `header` varchar(255) NOT NULL,
  `content` text NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `active` tinyint(1) NOT NULL DEFAULT '0',
  `show_on` enum('home','dashboard','both') NOT NULL DEFAULT 'home',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.notification_settings
CREATE TABLE IF NOT EXISTS `notification_settings` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `type` varchar(15) NOT NULL,
  `account_id` int(11) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `account_id_type` (`account_id`,`type`),
  KEY `account_id` (`account_id`)
) ENGINE=InnoDB AUTO_INCREMENT=221 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.notifications
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.payouts
CREATE TABLE IF NOT EXISTS `payouts` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `account_id` (`account_id`,`completed`)
) ENGINE=InnoDB AUTO_INCREMENT=32 DEFAULT CHARSET=latin1;

-- Data exporting was unselected.

-- Dumping structure for table mpos.payouts_mm
CREATE TABLE IF NOT EXISTS `payouts_mm` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=35 DEFAULT CHARSET=latin1;

-- Data exporting was unselected.

-- Dumping structure for table mpos.payouts_mm1
CREATE TABLE IF NOT EXISTS `payouts_mm1` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=14 DEFAULT CHARSET=latin1;

-- Data exporting was unselected.

-- Dumping structure for table mpos.payouts_mm2
CREATE TABLE IF NOT EXISTS `payouts_mm2` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- Data exporting was unselected.

-- Dumping structure for table mpos.payouts_mm3
CREATE TABLE IF NOT EXISTS `payouts_mm3` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- Data exporting was unselected.

-- Dumping structure for table mpos.payouts_mm4
CREATE TABLE IF NOT EXISTS `payouts_mm4` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- Data exporting was unselected.

-- Dumping structure for table mpos.payouts_mm5
CREATE TABLE IF NOT EXISTS `payouts_mm5` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- Data exporting was unselected.

-- Dumping structure for table mpos.payouts_mm6
CREATE TABLE IF NOT EXISTS `payouts_mm6` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- Data exporting was unselected.

-- Dumping structure for table mpos.pool_worker
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
) ENGINE=InnoDB AUTO_INCREMENT=7909 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.settings
CREATE TABLE IF NOT EXISTS `settings` (
  `name` varchar(255) NOT NULL,
  `value` text,
  PRIMARY KEY (`name`),
  UNIQUE KEY `setting` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Seed settings rows needed by a fresh automated install. DB_VERSION keeps
-- the cronjobs' shared.inc.php gate
-- (DB_VERSION constant from public/include/version.inc.php)
-- doesn't abort every cron on a fresh install with "Cronjob is
-- currently disabled due to required upgrades." backups_enabled defaults
-- the deploy backup timer to on while still allowing the admin UI to pause it.
INSERT INTO `settings` (`name`, `value`) VALUES ('DB_VERSION', '0.0.5')
  ON DUPLICATE KEY UPDATE `value` = '0.0.5';
INSERT IGNORE INTO `settings` (`name`, `value`) VALUES ('backups_enabled', '1');

-- Dumping structure for table mpos.shares
CREATE TABLE IF NOT EXISTS `shares` (
  `id` bigint(30) NOT NULL AUTO_INCREMENT,
  `rem_host` varchar(255) NOT NULL,
  `username` varchar(120) NOT NULL,
  `our_result` enum('Y','N') NOT NULL,
  `upstream_result` enum('Y','N') DEFAULT NULL,
  `reason` varchar(50) DEFAULT NULL,
  `solution` varchar(257) CHARACTER SET ucs2 COLLATE ucs2_unicode_ci NOT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `time` (`time`),
  KEY `upstream_result` (`upstream_result`),
  KEY `our_result` (`our_result`),
  KEY `username` (`username`),
  KEY `shares_username` (`username`(10))
) ENGINE=InnoDB AUTO_INCREMENT=1283992873 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.shares_archive
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
) ENGINE=InnoDB AUTO_INCREMENT=1334788133 DEFAULT CHARSET=utf8 COMMENT='Archive shares for potential later debugging purposes';

-- Data exporting was unselected.

-- Dumping structure for table mpos.shares_archive_mm
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
) ENGINE=InnoDB AUTO_INCREMENT=59013920 DEFAULT CHARSET=utf8 COMMENT='Archive shares for potential later debugging purposes';

-- Data exporting was unselected.

-- Dumping structure for table mpos.shares_archive_mm1
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
) ENGINE=InnoDB AUTO_INCREMENT=58910015 DEFAULT CHARSET=utf8 COMMENT='Archive shares for potential later debugging purposes';

-- Data exporting was unselected.

-- Dumping structure for table mpos.shares_archive_mm2
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='Archive shares for potential later debugging purposes';

-- Data exporting was unselected.

-- Dumping structure for table mpos.shares_archive_mm3
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
) ENGINE=InnoDB AUTO_INCREMENT=58840340 DEFAULT CHARSET=utf8 COMMENT='Archive shares for potential later debugging purposes';

-- Data exporting was unselected.

-- Dumping structure for table mpos.shares_archive_mm4
CREATE TABLE IF NOT EXISTS `shares_archive_mm4` (
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
) ENGINE=InnoDB AUTO_INCREMENT=59003630 DEFAULT CHARSET=utf8 COMMENT='Archive shares for potential later debugging purposes';

-- Data exporting was unselected.

-- Dumping structure for table mpos.shares_archive_mm5
CREATE TABLE IF NOT EXISTS `shares_archive_mm5` (
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
) ENGINE=InnoDB AUTO_INCREMENT=58933569 DEFAULT CHARSET=utf8 COMMENT='Archive shares for potential later debugging purposes';

-- Data exporting was unselected.

-- Dumping structure for table mpos.shares_archive_mm6
CREATE TABLE IF NOT EXISTS `shares_archive_mm6` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='Archive shares for potential later debugging purposes';

-- Data exporting was unselected.

-- Dumping structure for table mpos.shares_mm
CREATE TABLE IF NOT EXISTS `shares_mm` (
  `id` bigint(30) NOT NULL AUTO_INCREMENT,
  `rem_host` varchar(255) NOT NULL,
  `username` varchar(120) NOT NULL,
  `our_result` enum('Y','N') NOT NULL,
  `upstream_result` enum('Y','N') DEFAULT NULL,
  `reason` varchar(50) DEFAULT NULL,
  `solution` varchar(257) CHARACTER SET ucs2 COLLATE ucs2_unicode_ci NOT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `time` (`time`),
  KEY `upstream_result` (`upstream_result`),
  KEY `our_result` (`our_result`),
  KEY `username` (`username`),
  KEY `shares_username` (`username`(10))
) ENGINE=InnoDB AUTO_INCREMENT=1280212719 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.shares_mm1
CREATE TABLE IF NOT EXISTS `shares_mm1` (
  `id` bigint(30) NOT NULL AUTO_INCREMENT,
  `rem_host` varchar(255) NOT NULL,
  `username` varchar(120) NOT NULL,
  `our_result` enum('Y','N') NOT NULL,
  `upstream_result` enum('Y','N') DEFAULT NULL,
  `reason` varchar(50) DEFAULT NULL,
  `solution` varchar(257) CHARACTER SET ucs2 COLLATE ucs2_unicode_ci NOT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `time` (`time`),
  KEY `upstream_result` (`upstream_result`),
  KEY `our_result` (`our_result`),
  KEY `username` (`username`),
  KEY `shares_username` (`username`(10))
) ENGINE=InnoDB AUTO_INCREMENT=1278647341 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.shares_mm2
CREATE TABLE IF NOT EXISTS `shares_mm2` (
  `id` bigint(30) NOT NULL AUTO_INCREMENT,
  `rem_host` varchar(255) NOT NULL,
  `username` varchar(120) NOT NULL,
  `our_result` enum('Y','N') NOT NULL,
  `upstream_result` enum('Y','N') DEFAULT NULL,
  `reason` varchar(50) DEFAULT NULL,
  `solution` varchar(257) CHARACTER SET ucs2 COLLATE ucs2_unicode_ci NOT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `time` (`time`),
  KEY `upstream_result` (`upstream_result`),
  KEY `our_result` (`our_result`),
  KEY `username` (`username`),
  KEY `shares_username` (`username`(10))
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.shares_mm3
CREATE TABLE IF NOT EXISTS `shares_mm3` (
  `id` bigint(30) NOT NULL AUTO_INCREMENT,
  `rem_host` varchar(255) NOT NULL,
  `username` varchar(120) NOT NULL,
  `our_result` enum('Y','N') NOT NULL,
  `upstream_result` enum('Y','N') DEFAULT NULL,
  `reason` varchar(50) DEFAULT NULL,
  `solution` varchar(257) CHARACTER SET ucs2 COLLATE ucs2_unicode_ci NOT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `time` (`time`),
  KEY `upstream_result` (`upstream_result`),
  KEY `our_result` (`our_result`),
  KEY `username` (`username`),
  KEY `shares_username` (`username`(10))
) ENGINE=InnoDB AUTO_INCREMENT=1272029501 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.shares_mm4
CREATE TABLE IF NOT EXISTS `shares_mm4` (
  `id` bigint(30) NOT NULL AUTO_INCREMENT,
  `rem_host` varchar(255) NOT NULL,
  `username` varchar(120) NOT NULL,
  `our_result` enum('Y','N') NOT NULL,
  `upstream_result` enum('Y','N') DEFAULT NULL,
  `reason` varchar(50) DEFAULT NULL,
  `solution` varchar(257) CHARACTER SET ucs2 COLLATE ucs2_unicode_ci NOT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `time` (`time`),
  KEY `upstream_result` (`upstream_result`),
  KEY `our_result` (`our_result`),
  KEY `username` (`username`),
  KEY `shares_username` (`username`(10))
) ENGINE=InnoDB AUTO_INCREMENT=1251752263 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.shares_mm5
CREATE TABLE IF NOT EXISTS `shares_mm5` (
  `id` bigint(30) NOT NULL AUTO_INCREMENT,
  `rem_host` varchar(255) NOT NULL,
  `username` varchar(120) NOT NULL,
  `our_result` enum('Y','N') NOT NULL,
  `upstream_result` enum('Y','N') DEFAULT NULL,
  `reason` varchar(50) DEFAULT NULL,
  `solution` varchar(257) CHARACTER SET ucs2 COLLATE ucs2_unicode_ci NOT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `time` (`time`),
  KEY `upstream_result` (`upstream_result`),
  KEY `our_result` (`our_result`),
  KEY `username` (`username`),
  KEY `shares_username` (`username`(10))
) ENGINE=InnoDB AUTO_INCREMENT=1230347454 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.shares_mm6
CREATE TABLE IF NOT EXISTS `shares_mm6` (
  `id` bigint(30) NOT NULL AUTO_INCREMENT,
  `rem_host` varchar(255) NOT NULL,
  `username` varchar(120) NOT NULL,
  `our_result` enum('Y','N') NOT NULL,
  `upstream_result` enum('Y','N') DEFAULT NULL,
  `reason` varchar(50) DEFAULT NULL,
  `solution` varchar(257) CHARACTER SET ucs2 COLLATE ucs2_unicode_ci NOT NULL,
  `difficulty` float NOT NULL DEFAULT '0',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `time` (`time`),
  KEY `upstream_result` (`upstream_result`),
  KEY `our_result` (`our_result`),
  KEY `username` (`username`),
  KEY `shares_username` (`username`(10))
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.statistics_shares
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
) ENGINE=InnoDB AUTO_INCREMENT=12676266 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.templates
CREATE TABLE IF NOT EXISTS `templates` (
  `template` varchar(255) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT '0',
  `content` mediumtext,
  `modified_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`template`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.token_types
CREATE TABLE IF NOT EXISTS `token_types` (
  `id` tinyint(4) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(25) NOT NULL,
  `expiration` int(11) DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8;

INSERT INTO `token_types` (`id`, `name`, `expiration`) VALUES
  (1, 'password_reset', 3600),
  (2, 'confirm_email', 0),
  (3, 'invitation', 0),
  (4, 'account_unlock', 0),
  (5, 'account_edit', 3600),
  (6, 'change_pw', 3600),
  (7, 'withdraw_funds', 3600)
ON DUPLICATE KEY UPDATE `name`=VALUES(`name`), `expiration`=VALUES(`expiration`);

-- Dumping structure for table mpos.tokens
CREATE TABLE IF NOT EXISTS `tokens` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `token` varchar(65) NOT NULL,
  `type` tinyint(4) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `token` (`token`),
  KEY `account_id` (`account_id`)
) ENGINE=InnoDB AUTO_INCREMENT=1201 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.transactions
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
) ENGINE=InnoDB AUTO_INCREMENT=18949982 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.transactions_mm
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
) ENGINE=InnoDB AUTO_INCREMENT=20141200 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.transactions_mm1
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
) ENGINE=InnoDB AUTO_INCREMENT=24843299 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.transactions_mm2
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.transactions_mm3
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
) ENGINE=InnoDB AUTO_INCREMENT=50955381 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.transactions_mm4
CREATE TABLE IF NOT EXISTS `transactions_mm4` (
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
) ENGINE=InnoDB AUTO_INCREMENT=35389332 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.transactions_mm5
CREATE TABLE IF NOT EXISTS `transactions_mm5` (
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
) ENGINE=InnoDB AUTO_INCREMENT=18071954 DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

-- Dumping structure for table mpos.transactions_mm6
CREATE TABLE IF NOT EXISTS `transactions_mm6` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Data exporting was unselected.

/*!40103 SET TIME_ZONE=IFNULL(@OLD_TIME_ZONE, 'system') */;
/*!40101 SET SQL_MODE=IFNULL(@OLD_SQL_MODE, '') */;
/*!40014 SET FOREIGN_KEY_CHECKS=IFNULL(@OLD_FOREIGN_KEY_CHECKS, 1) */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40111 SET SQL_NOTES=IFNULL(@OLD_SQL_NOTES, 1) */;
