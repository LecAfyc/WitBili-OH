/**
 * 更新检查与公告拉取
 *
 */

import { httpGetText } from './CommonApi';
import { bundleManager } from '@kit.AbilityKit';

// ===== 类型 =====

export interface LatestVersionInfo {
  versionCode: number;
  versionName: string;
  releaseTimeName: string;
  descriptionLines: string[];
}

export interface CanaryVersionInfo {
  versionCode: number;
  versionName: string;
  releaseTimeName: string;
}

export interface BroadcastInfo {
  releaseTimeStamp: number;
  expiredTimeStamp: number;
  contentLines: string[];
}

export interface UpdateCheckResult {
  latest: LatestVersionInfo | null;
  canary: CanaryVersionInfo | null;
  broadcast: BroadcastInfo | null;
}

// ===== 常量 =====

const UPDATE_URLS: string[] = [
  'https://gh-proxy.com/https://raw.githubusercontent.com/LecAfyc/WitBili-Update-Check/refs/heads/master/update.json',
  'https://raw.githubusercontent.com/LecAfyc/WitBili-Update-Check/refs/heads/master/update.json',
  'https://github.dpik.top/https://raw.githubusercontent.com/LecAfyc/WitBili-Update-Check/refs/heads/master/update.json'
];

/** bundleManager 读取失败时的兜底版本号（需与 AppScope/app.json5 同步） */
const FALLBACK_VERSION_CODE: number = 1001005;

/** 持久化键：已忽略的稳定版 versionCode */
const KEY_IGNORED_VERSION: string = 'ignoredUpdateVersionCode';

/** 持久化键：已显示过的公告 releaseTimeStamp（JSON 数组字符串） */
const KEY_SHOWN_BROADCASTS: string = 'shownBroadcastTimestamps';

// ===== 解析工具 =====

function parseStringArray(raw: Object): string[] {
  let result: string[] = [];
  if (Array.isArray(raw)) {
    let arr: Object[] = raw as Object[];
    for (let i = 0; i < arr.length; i++) {
      result.push(arr[i] as string);
    }
  }
  return result;
}

function parseLatestInfo(raw: Object): LatestVersionInfo {
  let obj: Record<string, Object> = raw as Record<string, Object>;
  let info: LatestVersionInfo = {
    versionCode: (obj['versionCode'] as number) ?? 0,
    versionName: (obj['versionName'] as string) ?? '',
    releaseTimeName: (obj['releaseTimeName'] as string) ?? '',
    descriptionLines: parseStringArray(obj['descriptionLines'])
  };
  return info;
}

function parseCanaryInfo(raw: Object): CanaryVersionInfo {
  let obj: Record<string, Object> = raw as Record<string, Object>;
  let info: CanaryVersionInfo = {
    versionCode: (obj['versionCode'] as number) ?? 0,
    versionName: (obj['versionName'] as string) ?? '',
    releaseTimeName: (obj['releaseTimeName'] as string) ?? ''
  };
  return info;
}

function parseBroadcast(raw: Object): BroadcastInfo {
  let obj: Record<string, Object> = raw as Record<string, Object>;
  let info: BroadcastInfo = {
    releaseTimeStamp: (obj['releaseTimeStamp'] as number) ?? 0,
    expiredTimeStamp: (obj['expiredTimeStamp'] as number) ?? 0,
    contentLines: parseStringArray(obj['contentLines'])
  };
  return info;
}

function parseUpdateJson(text: string): UpdateCheckResult {
  let result: UpdateCheckResult = { latest: null, canary: null, broadcast: null };
  let root: Record<string, Object> = JSON.parse(text) as Record<string, Object>;

  let latestObj: Object = root['latestVersionInfo'];
  if (latestObj !== undefined && latestObj !== null) {
    result.latest = parseLatestInfo(latestObj);
  }

  let canaryObj: Object = root['canaryVersionInfo'];
  if (canaryObj !== undefined && canaryObj !== null) {
    result.canary = parseCanaryInfo(canaryObj);
  }

  let broadcastObj: Object = root['broadcasts'];
  if (broadcastObj !== undefined && broadcastObj !== null) {
    result.broadcast = parseBroadcast(broadcastObj);
  }

  return result;
}

// ===== 拉取 =====

export async function fetchUpdateJsonText(): Promise<string> {
  for (let i = 0; i < UPDATE_URLS.length; i++) {
    try {
      let text: string = await httpGetText(UPDATE_URLS[i]);
      return text;
    } catch (e) {
      console.warn('[UpdateApi] 拉取失败: ' + UPDATE_URLS[i]);
    }
  }
  throw new Error('[UpdateApi] 所有更新源均拉取失败');
}

export async function fetchUpdateCheck(): Promise<UpdateCheckResult | null> {
  try {
    let text: string = await fetchUpdateJsonText();
    return parseUpdateJson(text);
  } catch (e) {
    console.warn('[UpdateApi] 获取更新信息失败: ' + JSON.stringify(e));
    return null;
  }
}

// ===== 当前版本号 =====

export function getCurrentVersionCode(): number {
  try {
    let info: bundleManager.BundleInfo =
      bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    return info.versionCode;
  } catch (e) {
    console.warn('[UpdateApi] 读取版本号失败，使用兜底值: ' + FALLBACK_VERSION_CODE);
    return FALLBACK_VERSION_CODE;
  }
}

// ===== 时间（按秒） =====

export function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

// ===== 忽略版本持久化 =====

export function isVersionIgnored(code: number): boolean {
  let ignored: number | undefined = AppStorage.get<number>(KEY_IGNORED_VERSION);
  return ignored !== undefined && ignored === code;
}

export function setVersionIgnored(code: number): void {
  AppStorage.set<number>(KEY_IGNORED_VERSION, code);
}

// ===== 公告去重持久化 =====

export function getShownBroadcastTimestamps(): number[] {
  let raw: string | undefined = AppStorage.get<string>(KEY_SHOWN_BROADCASTS);
  if (raw === undefined || raw === null || raw.length === 0) {
    return [];
  }
  try {
    let parsed: Object = JSON.parse(raw) as Object;
    if (Array.isArray(parsed)) {
      let arr: Object[] = parsed as Object[];
      let result: number[] = [];
      for (let i = 0; i < arr.length; i++) {
        result.push(arr[i] as number);
      }
      return result;
    }
  } catch (e) {
    console.warn('[UpdateApi] 解析已显示公告时间戳失败');
  }
  return [];
}

export function isBroadcastShown(releaseTimeStamp: number): boolean {
  let shown: number[] = getShownBroadcastTimestamps();
  for (let i = 0; i < shown.length; i++) {
    if (shown[i] === releaseTimeStamp) {
      return true;
    }
  }
  return false;
}

export function markBroadcastShown(releaseTimeStamp: number): void {
  let shown: number[] = getShownBroadcastTimestamps();
  shown.push(releaseTimeStamp);
  AppStorage.set<string>(KEY_SHOWN_BROADCASTS, JSON.stringify(shown));
}
