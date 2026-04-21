<?php
(!cfip()) ? header('HTTP/1.1 401 Unauthorized') : 0;

// Load PHPMailer classes
require_once(BASEPATH . 'include/lib/PHPMailer/src/PHPMailer.php');
require_once(BASEPATH . 'include/lib/PHPMailer/src/SMTP.php');
require_once(BASEPATH . 'include/lib/PHPMailer/src/Exception.php');

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\SMTP;
use PHPMailer\PHPMailer\Exception;

class Mail extends Base {
  /**
  * Mail form contact site admin
  * @param senderName string senderName
  * @param senderEmail string senderEmail
  * @param senderSubject string senderSubject
  * @param senderMessage string senderMessage
  * @param email string config Email address
  * @param subject string header subject
  * @return bool
  **/
  public function contactform($senderName, $senderEmail, $senderSubject, $senderMessage) {
    $this->debug->append("STA " . __METHOD__, 4);
    if (preg_match('/[^a-z_\.\!\?\-0-9\\s ]/i', $senderName)) {
      $this->setErrorMessage($this->getErrorMsg('E0024'));
      return false;
    }
    if (empty($senderEmail) || !filter_var($senderEmail, FILTER_VALIDATE_EMAIL)) {
      $this->setErrorMessage($this->getErrorMsg('E0023'));
      return false;
    }
    if (preg_match('/[^a-z_\.\!\?\-0-9\\s ]/i', $senderSubject)) {
      $this->setErrorMessage($this->getErrorMsg('E0034'));
      return false;
    }
    if (strlen(strip_tags($senderMessage)) < strlen($senderMessage)) {
      $this->setErrorMessage($this->getErrorMsg('E0024'));
      return false;
    }
    $aData['senderName'] = $senderName;
    $aData['senderEmail'] = $senderEmail;
    $aData['senderSubject'] = $senderSubject;
    $aData['senderMessage'] = $senderMessage;
    $aData['email'] = $this->setting->getValue('website_email');
    $aData['subject'] = 'Contact Form';
      if ($this->sendMail('contactform/body', $aData)) {
        return true;
     } else {
       $this->setErrorMessage( 'Unable to send email' );
       return false;
     }
    return false;
  }

  /**
   * Send a mail with templating via Smarty
   * @param template string Template name within the mail folder, no extension
   * @param aData array Data array with some required fields
   *     SUBJECT : Mail Subject
   *     email   : Destination address
   **/
  public function sendMail($template, $aData) {
    // Make sure we don't load a cached filed
    $this->smarty->clearCache(BASEPATH . 'templates/mail/' . $template . '.tpl');
    $this->smarty->clearCache(BASEPATH . 'templates/mail/subject.tpl');
    $this->smarty->assign('WEBSITENAME', $this->setting->getValue('website_name'));
    $this->smarty->assign('SUBJECT', $aData['subject']);
    $this->smarty->assign('DATA', $aData);
    
    // Check if SMTP is enabled
    $smtp_enabled = $this->setting->getValue('smtp_enabled');
    
    if ($smtp_enabled) {
      return $this->sendMailSMTP($template, $aData);
    } else {
      return $this->sendMailNative($template, $aData);
    }
  }
  
  /**
   * Send email using native PHP mail() function
   */
  private function sendMailNative($template, $aData) {
    $headers = 'From: ' . $this->setting->getValue('website_name') . '<' . $this->setting->getValue('website_email') . ">\n";
    $headers .= "MIME-Version: 1.0\n";
    $headers .= "Content-Type: text/html; charset=ISO-8859-1\r\n";
    if (strlen(@$aData['senderName']) > 0 && @strlen($aData['senderEmail']) > 0 )
      $headers .= 'Reply-To: ' . $aData['senderName'] . ' <' . $aData['senderEmail'] . ">\n";
    if (mail($aData['email'], $this->smarty->fetch(BASEPATH . 'templates/mail/subject.tpl'), $this->smarty->fetch(BASEPATH . 'templates/mail/' . $template . '.tpl'), $headers))
      return true;
    $this->setErrorMessage($this->sqlError('E0031'));
    return false;
  }
  
  /**
   * Send email using SMTP (PHPMailer)
   */
  private function sendMailSMTP($template, $aData) {
    $mail = new PHPMailer(true);
    
    try {
      // Server settings
      $mail->SMTPDebug = 0; // Set to 2 for debugging
      $mail->isSMTP();
      $mail->Host = $this->setting->getValue('smtp_host');
      $mail->SMTPAuth = true;
      $mail->Username = $this->setting->getValue('smtp_username');
      $mail->Password = $this->setting->getValue('smtp_password');
      
      // Encryption and port
      $smtp_secure = $this->setting->getValue('smtp_secure');
      if ($smtp_secure == 'tls') {
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port = 587;
      } else if ($smtp_secure == 'ssl') {
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_SMTPS;
        $mail->Port = 465;
      } else {
        $mail->Port = $this->setting->getValue('smtp_port') ?: 587;
      }
      
      // Recipients
      $mail->setFrom($this->setting->getValue('website_email'), $this->setting->getValue('website_name'));
      $mail->addAddress($aData['email']);
      
      // Reply-To if provided
      if (strlen(@$aData['senderName']) > 0 && @strlen($aData['senderEmail']) > 0) {
        $mail->addReplyTo($aData['senderEmail'], $aData['senderName']);
      }
      
      // Content
      $mail->isHTML(true);
      $mail->Subject = $this->smarty->fetch(BASEPATH . 'templates/mail/subject.tpl');
      $mail->Body = $this->smarty->fetch(BASEPATH . 'templates/mail/' . $template . '.tpl');
      
      $mail->send();
      return true;
      
    } catch (Exception $e) {
      $this->setErrorMessage("Mailer Error: {$mail->ErrorInfo}");
      return false;
    }
  }
}

// Make our class available automatically
$mail = new Mail ();
$mail->setDebug($debug);
$mail->setMysql($mysqli);
$mail->setSmarty($smarty);
$mail->setConfig($config);
$mail->setSetting($setting);
$mail->setErrorCodes($aErrorCodes);
?>
