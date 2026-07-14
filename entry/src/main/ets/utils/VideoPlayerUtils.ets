/**
 * 视频播放器工具函数
 *
 * 包含时间格式化、电池图标映射、IJKPlayer 配置等通用工具。
 */

import {
  IjkMediaPlayer,
} from '@ohos/ijkplayer';
import { getCookieString } from '../api/CookiesApi';
import { HEADERS } from '../api/CommonApi';

// ===== 时间格式化 =====

export function formatTime(ms: number): string {
  if (ms < 0) {
    ms = 0;
  }
  let totalSec: number = Math.floor(ms / 1000);
  let min: number = Math.floor(totalSec / 60);
  let sec: number = totalSec % 60;
  return min.toString().padStart(2, '0') + ':' + sec.toString().padStart(2, '0');
}

// ===== 电池图标 =====

export function getBatteryIcon(level: number): Resource {
  if (level <= 5) {
    return $r('sys.symbol.battery_5percent');
  }
  if (level <= 10) {
    return $r('sys.symbol.battery_10percent');
  }
  if (level <= 15) {
    return $r('sys.symbol.battery_15percent');
  }
  if (level <= 20) {
    return $r('sys.symbol.battery_20percent');
  }
  if (level <= 30) {
    return $r('sys.symbol.battery_30percent');
  }
  if (level <= 40) {
    return $r('sys.symbol.battery_40percent');
  }
  if (level <= 50) {
    return $r('sys.symbol.battery_50percent');
  }
  if (level <= 60) {
    return $r('sys.symbol.battery_60percent');
  }
  if (level <= 70) {
    return $r('sys.symbol.battery_70percent');
  }
  if (level <= 80) {
    return $r('sys.symbol.battery_80percent');
  }
  if (level <= 90) {
    return $r('sys.symbol.battery_90percent');
  }
  return $r('sys.symbol.battery_100percent');
}

// ===== IJKPlayer 配置 =====

export function applyDefaultPlayerOptions(player: IjkMediaPlayer): void {
  player.setOption('4', 'start-on-prepared', '0');
  player.setOption('4', 'mediacodec-all-videos', '1');
  player.setOption('4', 'mediacodec-auto-rotate', '1');
  player.setOption('4', 'mediacodec-handle-resolution-change', '1');
  player.setOption('4', 'enable-accurate-seek', '0');
  player.setOption('4', 'packet-buffering', '1');
  player.setOption('4', 'max-buffer-size', '15728640');
  player.setOption('4', 'min-frames', '25');
  player.setOption('4', 'framedrop', '1');
  player.setOption('4', 'max-fps', '30');
  player.setOption('4', 'sync-av-start', '1');
  player.setOption('4', 'infbuf', '0');
  player.setOption('1', 'timeout', '15000000');
  player.setOption('1', 'connect_timeout', '15000000');
  player.setOption('1', 'addrinfo_timeout', '15000000');
  player.setOption('1', 'dns_cache_timeout', '15000000');
  player.setOption('4', "framedrop", "5");
  player.setOption('4', "soundtouch", "1");
}

export function setupPlayerHeaders(player: IjkMediaPlayer): void {
  let cookieStr: string = getCookieString();
  let headers: Map<string, string> = new Map([
    ['user_agent', HEADERS['User-Agent']],
    ['origin', HEADERS['Origin']],
    ['referer', HEADERS['Referer']],
    ['cookies', cookieStr]
  ]);
  player.setDataSourceHeader(headers);
  player.setOption('1', 'user-agent', HEADERS['User-Agent']);
  player.setOption('1', 'referer', HEADERS['Referer']);
  player.setOption('1', 'cookies', cookieStr);
}
