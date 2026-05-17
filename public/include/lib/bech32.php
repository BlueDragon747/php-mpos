<?php
/*
 * Bech32 (BIP173) segwit-address validator for MPOS.
 *
 * Ported from the BIP173 reference Python implementation shipped with
 * Blakestream-Eliopool-15.21
 * (deploy-bundle/eloipool/bitcoin/segwit_addr.py), which is itself Pieter
 * Wuille's reference under the MIT-equivalent BIP licence.
 *
 * Pure PHP, no extensions required. Tested on PHP 7.1+ / 8.1.
 *
 * For MPOS we only need to answer "is this string a well-formed bech32
 * segwit address in one of these HRPs?" — we never build scriptPubKeys in
 * PHP because the Blakecoin daemon is the one that actually sends the
 * payout. So `Bech32::isValid()` is the hot path; `Bech32::decode()` is
 * provided for tests and future callers.
 *
 * A caller that also wants legacy base58 support should try legacy
 * validation first, then fall through to this helper.
 */

class Bech32 {

  /** BIP173 charset — index i ↔ 5-bit value i. */
  const CHARSET = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

  /** BIP173 generator constants for the polymod. */
  const GEN = array(0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3);

  /** Maximum bech32 address length (BIP173). */
  const MAX_LEN = 90;

  /**
   * True iff $addr is a valid bech32 segwit address whose HRP is in
   * $allowedHrps. Applies both the BIP173 checksum and the BIP141 witness
   * version / program-size rules.
   *
   * @param string[] $allowedHrps e.g. array('blc', 'tblc')
   * @param string   $addr        user-supplied candidate address
   * @return bool
   */
  public static function isValid(array $allowedHrps, $addr) {
    return self::decode($allowedHrps, $addr) !== null;
  }

  /**
   * Parse and validate a bech32 segwit address.
   *
   * @return array|null  null on any validation failure; otherwise an array
   *   with keys 'hrp' (string), 'witver' (int 0..16) and 'witprog' (raw
   *   byte string of length 2..40).
   */
  public static function decode(array $allowedHrps, $addr) {
    if (!is_string($addr)) return null;

    $parts = self::bech32Decode($addr);
    if ($parts === null) return null;
    list($hrp, $data) = $parts;

    if (!in_array($hrp, $allowedHrps, true)) return null;
    if (count($data) < 1) return null;

    $witver = $data[0];
    if ($witver < 0 || $witver > 16) return null;

    $prog5 = array_slice($data, 1);
    $prog8 = self::convertBits($prog5, 5, 8, false);
    if ($prog8 === null) return null;

    $len = count($prog8);
    if ($len < 2 || $len > 40) return null;
    // BIP141: witness v0 programs are exactly 20 (P2WPKH) or 32 (P2WSH) bytes.
    if ($witver === 0 && $len !== 20 && $len !== 32) return null;

    $witprog = '';
    foreach ($prog8 as $b) $witprog .= chr($b);

    return array('hrp' => $hrp, 'witver' => $witver, 'witprog' => $witprog);
  }

  /**
   * Low-level bech32 decode — returns array($hrp, $data_without_checksum)
   * or null on failure. $data entries are 5-bit integers 0..31.
   */
  private static function bech32Decode($bech) {
    $len = strlen($bech);
    if ($len === 0 || $len > self::MAX_LEN) return null;

    // Printable-ASCII check + mixed-case rejection (BIP173).
    $hasLower = false;
    $hasUpper = false;
    for ($i = 0; $i < $len; $i++) {
      $o = ord($bech[$i]);
      if ($o < 33 || $o > 126) return null;
      if ($o >= 0x61 && $o <= 0x7a) $hasLower = true;
      if ($o >= 0x41 && $o <= 0x5a) $hasUpper = true;
    }
    if ($hasLower && $hasUpper) return null;
    $bech = strtolower($bech);

    // Separator is the LAST '1'. HRP is non-empty; at least 6 data chars
    // for the checksum must follow.
    $pos = strrpos($bech, '1');
    if ($pos === false || $pos < 1 || $pos + 7 > $len) return null;

    $hrp = substr($bech, 0, $pos);
    $dataStr = substr($bech, $pos + 1);
    $dataLen = strlen($dataStr);

    $data = array();
    $charset = self::CHARSET;
    for ($i = 0; $i < $dataLen; $i++) {
      $p = strpos($charset, $dataStr[$i]);
      if ($p === false) return null;
      $data[] = $p;
    }

    if (!self::verifyChecksum($hrp, $data)) return null;

    return array($hrp, array_slice($data, 0, count($data) - 6));
  }

  /**
   * BIP173 polymod over a list of 5-bit values. Returns a 30-bit integer.
   * Fits comfortably in PHP's 64-bit native int on any modern platform.
   */
  private static function polymod(array $values) {
    $chk = 1;
    foreach ($values as $v) {
      $b = $chk >> 25;
      $chk = (($chk & 0x1ffffff) << 5) ^ $v;
      for ($i = 0; $i < 5; $i++) {
        if (($b >> $i) & 1) $chk ^= self::GEN[$i];
      }
    }
    return $chk;
  }

  /** BIP173 HRP expansion: high bits + 0 separator + low bits. */
  private static function hrpExpand($hrp) {
    $hi = array();
    $lo = array();
    $n = strlen($hrp);
    for ($i = 0; $i < $n; $i++) {
      $c = ord($hrp[$i]);
      $hi[] = $c >> 5;
      $lo[] = $c & 31;
    }
    return array_merge($hi, array(0), $lo);
  }

  private static function verifyChecksum($hrp, array $data) {
    return self::polymod(array_merge(self::hrpExpand($hrp), $data)) === 1;
  }

  /**
   * BIP173 general base-conversion used to turn the 5-bit data payload
   * into the 8-bit witness program bytes. Returns null on invalid input.
   *
   * @return int[]|null
   */
  private static function convertBits(array $data, $fromBits, $toBits, $pad) {
    $acc = 0;
    $bits = 0;
    $ret = array();
    $maxv = (1 << $toBits) - 1;
    $maxAcc = (1 << ($fromBits + $toBits - 1)) - 1;
    foreach ($data as $v) {
      if ($v < 0 || ($v >> $fromBits) !== 0) return null;
      $acc = (($acc << $fromBits) | $v) & $maxAcc;
      $bits += $fromBits;
      while ($bits >= $toBits) {
        $bits -= $toBits;
        $ret[] = ($acc >> $bits) & $maxv;
      }
    }
    if ($pad) {
      if ($bits > 0) $ret[] = ($acc << ($toBits - $bits)) & $maxv;
    } elseif ($bits >= $fromBits || (($acc << ($toBits - $bits)) & $maxv) !== 0) {
      return null;
    }
    return $ret;
  }
}
