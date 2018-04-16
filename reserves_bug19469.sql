-- MySQL dump 10.15  Distrib 10.0.32-MariaDB, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: koha_kohadev
-- ------------------------------------------------------
-- Server version	10.0.32-MariaDB-0+deb8u1

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `reserves`
--

DROP TABLE IF EXISTS `reserves`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `reserves` (
  `reserve_id` int(11) NOT NULL AUTO_INCREMENT,
  `borrowernumber` int(11) NOT NULL DEFAULT '0',
  `reservedate` date DEFAULT NULL,
  `biblionumber` int(11) NOT NULL DEFAULT '0',
  `branchcode` varchar(10) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `notificationdate` date DEFAULT NULL,
  `reminderdate` date DEFAULT NULL,
  `cancellationdate` date DEFAULT NULL,
  `reservenotes` longtext COLLATE utf8mb4_unicode_ci,
  `priority` smallint(6) DEFAULT NULL,
  `found` varchar(1) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `itemnumber` int(11) DEFAULT NULL,
  `waitingdate` date DEFAULT NULL,
  `expirationdate` date DEFAULT NULL,
  `lowestPriority` tinyint(1) NOT NULL DEFAULT '0',
  `suspend` tinyint(1) NOT NULL DEFAULT '0',
  `suspend_until` datetime DEFAULT NULL,
  `itemtype` varchar(10) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`reserve_id`),
  KEY `priorityfoundidx` (`priority`,`found`),
  KEY `borrowernumber` (`borrowernumber`),
  KEY `biblionumber` (`biblionumber`),
  KEY `itemnumber` (`itemnumber`),
  KEY `branchcode` (`branchcode`),
  KEY `itemtype` (`itemtype`),
  CONSTRAINT `reserves_ibfk_1` FOREIGN KEY (`borrowernumber`) REFERENCES `borrowers` (`borrowernumber`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `reserves_ibfk_2` FOREIGN KEY (`biblionumber`) REFERENCES `biblio` (`biblionumber`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `reserves_ibfk_3` FOREIGN KEY (`itemnumber`) REFERENCES `items` (`itemnumber`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `reserves_ibfk_4` FOREIGN KEY (`branchcode`) REFERENCES `branches` (`branchcode`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `reserves_ibfk_5` FOREIGN KEY (`itemtype`) REFERENCES `itemtypes` (`itemtype`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=25 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `reserves`
--

LOCK TABLES `reserves` WRITE;
/*!40000 ALTER TABLE `reserves` DISABLE KEYS */;
INSERT INTO `reserves` VALUES (16,4,'2018-04-16',394,'CPL',NULL,NULL,NULL,'',5,NULL,'2018-04-16 19:07:47',875,NULL,NULL,0,0,NULL,NULL),(17,18,'2018-04-16',394,'FRL',NULL,NULL,NULL,'',4,NULL,'2018-04-16 19:07:47',876,NULL,NULL,0,0,NULL,NULL),(18,31,'2018-04-16',394,'CPL',NULL,NULL,NULL,'',3,NULL,'2018-04-16 18:54:35',877,NULL,NULL,0,0,NULL,NULL),(19,21,'2018-04-16',394,'CPL',NULL,NULL,NULL,'',8,NULL,'2018-04-16 19:07:47',878,NULL,NULL,1,0,NULL,NULL),(20,45,'2018-04-16',394,'CPL',NULL,NULL,NULL,'',2,NULL,'2018-04-16 18:54:35',876,NULL,NULL,0,0,NULL,NULL),(21,5,'2018-04-16',394,'CPL',NULL,NULL,NULL,'',1,NULL,'2018-04-16 18:54:35',876,NULL,NULL,0,0,NULL,NULL),(22,15,'2018-04-16',394,'CPL',NULL,NULL,NULL,'',9,NULL,'2018-04-16 19:07:47',NULL,NULL,NULL,1,0,NULL,'BK'),(23,7,'2018-04-16',394,'FRL',NULL,NULL,NULL,'',6,NULL,'2018-04-16 19:07:47',877,NULL,NULL,0,0,NULL,NULL),(24,46,'2018-04-16',394,'CPL',NULL,NULL,NULL,'',7,NULL,'2018-04-16 19:07:47',875,NULL,NULL,0,0,NULL,NULL);
/*!40000 ALTER TABLE `reserves` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2018-04-16 16:10:26
