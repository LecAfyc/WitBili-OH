/**
 * Bilibili 扫码登录 API
 *
 */

import { http } from '@kit.NetworkKit';
import { ApiResponse, httpGet, httpPost, httpPostForm, HEADERS, RequestOptions, getCorrespondPath } from './CommonApi';
import {
  cookieMap as cookiesApiMap,
  putCookie as cookiesApiPut,
  saveToStorage as cookiesApiSave,
  checkCookies as cookiesApiCheckCookies
} from './CookiesApi';

// ===== 类型 =====

export interface QRCodeData {
  url: string; // 二维码内容（登录 URL）
  qrcodeKey: string; // 轮询用 key
}

export interface PollResult {
  code: number; // 0: 成功  86038: 过期  86090: 已扫码待确认  86101: 未扫码
  message: string;
  data: Object | null; // 登录成功时携带 cookies
}

/** 登录成功后的 cookie 信息 */
export interface LoginCookies {
  DedeUserID: string;
  DedeUserID__ckMd5: string;
  SESSDATA: string;
  bili_jct: string;
}


// ===== Cookie 管理 =====

/** Cookie 内存存储 */
export let cookieMap: Record<string, string> = {};

/** 从 cookieMap 重建 Cookie 请求头（包含 CookiesApi 中的环境 Cookie） */
function rebuildCookieHeader(): void {
  let parts: string[] = [];
  let keys: string[] = Object.keys(cookieMap);
  for (let i: number = 0; i < keys.length; i++) {
    parts.push(keys[i] + '=' + cookieMap[keys[i]]);
  }
  // 合并 CookiesApi 中尚未包含在 LoginApi.cookieMap 里的 Cookie
  let apiKeys: string[] = Object.keys(cookiesApiMap);
  for (let i: number = 0; i < apiKeys.length; i++) {
    let k: string = apiKeys[i];
    if (!cookieMap[k]) {
      parts.push(k + '=' + cookiesApiMap[k]);
      cookieMap[k] = cookiesApiMap[k];
    }
  }
  HEADERS['Cookie'] = parts.join('; ');
}

/** 从响应头中提取 Set-Cookie，合并到 LoginApi.cookieMap 和 CookiesApi */
function extractCookiesFromHeaders(headers: Record<string, Object>): void {
  // HarmonyOS http 返回 set-cookie 为数组（每条一条），也可能兼容旧版字符串
  let setCookie: Object | undefined = headers['set-cookie'] || headers['Set-Cookie'];
  if (!setCookie) {
    return;
  }

  let cookieItems: string[] = [];
  if (Array.isArray(setCookie)) {
    cookieItems = setCookie as string[];
  } else if (typeof setCookie === 'string') {
    cookieItems = (setCookie as string).split('\n');
  } else {
    return;
  }

  for (let i: number = 0; i < cookieItems.length; i++) {
    let item: string = cookieItems[i];
    // 取分号前的 name=value，忽略 Domain/Path/Expires 等属性
    let semicolonIdx: number = item.indexOf(';');
    let nvPart: string = semicolonIdx >= 0 ? item.substring(0, semicolonIdx) : item;
    let eqIdx: number = nvPart.indexOf('=');
    if (eqIdx > 0) {
      let name: string = nvPart.substring(0, eqIdx).trim();
      let value: string = nvPart.substring(eqIdx + 1).trim();
      if (name && value && !name.startsWith('.')) {
        cookieMap[name] = value;
        // 同步到 CookiesApi
        cookiesApiPut(name, value);
      }
    }
  }
  rebuildCookieHeader();
  cookiesApiSave();
}


// ===== LoginApi 专用 HTTP 封装（自动提取 Cookie） =====

/** 带 Cookie 提取的 GET */
function loginHttpGet(url: string): Promise<ApiResponse> {
  let opts: RequestOptions = { onHeaders: extractCookiesFromHeaders, logTag: '[LoginApi]' };
  return httpGet(url, opts);
}

/** 带 Cookie 提取的 POST */
function loginHttpPost(url: string): Promise<ApiResponse> {
  let opts: RequestOptions = { onHeaders: extractCookiesFromHeaders, logTag: '[LoginApi]' };
  return httpPost(url, opts);
}

/** 带 Cookie 提取的 POST Form */
function loginHttpPostForm(url: string, data: string): Promise<ApiResponse> {
  let opts: RequestOptions = { onHeaders: extractCookiesFromHeaders, logTag: '[LoginApi]' };
  return httpPostForm(url, data, opts);
}

// ===== QR 登录 API =====

/**
 * 获取登录二维码
 */
/**
 * 前置初始化：模拟浏览器 Cookie 环境
 * 委托给 CookiesApi.checkCookies() 获取完整的环境 Cookie（含 MurmurHash3 buvid_fp、bili_ticket），
 * 然后将生成的 Cookie 与 LoginApi.cookieMap 同步。
 */
export async function checkCookies(): Promise<void> {
  console.info('[Login] checkCookies: 委托 CookiesApi 生成环境 Cookie...');

  // 将 LoginApi 现有的 cookieMap 传给 CookiesApi（含登录态 Cookie）
  await cookiesApiCheckCookies(cookieMap);

  // 将 CookiesApi 生成的 Cookie 同步到 LoginApi.cookieMap
  let apiKeys: string[] = Object.keys(cookiesApiMap);
  for (let i: number = 0; i < apiKeys.length; i++) {
    let k: string = apiKeys[i];
    if (!cookieMap[k]) {
      cookieMap[k] = cookiesApiMap[k];
    }
  }

  // 重建 Cookie 头
  rebuildCookieHeader();
  console.info('[Login] checkCookies 完成, cookies:', Object.keys(cookieMap).join(', '));
}

export async function generateQRCode(): Promise<QRCodeData> {
  let url: string =
    'https://passport.bilibili.com/x/passport-login/web/qrcode/generate?source=main-fe-header&go_url=https:%2F%2Fwww.bilibili.com%2F';
  let resp: ApiResponse = await loginHttpGet(url);

  if (resp.code !== 0 || !resp.data) {
    throw new Error('获取二维码失败: ' + resp.message);
  }

  let data: Record<string, Object> = resp.data as Record<string, Object>;
  let qrcodeKey: string = data['qrcode_key'] as string || '';
  let qrUrl: string = data['url'] as string || '';

  if (!qrcodeKey || !qrUrl) {
    throw new Error('二维码数据不完整');
  }

  return { url: qrUrl, qrcodeKey: qrcodeKey };
}

/**
 * 轮询登录状态
 * GET https://passport.bilibili.com/x/passport-login/web/qrcode/poll
 *
 */
export async function pollLoginState(qrcodeKey: string): Promise<PollResult> {
  let url: string =
    'https://passport.bilibili.com/x/passport-login/web/qrcode/poll?source=main-fe-header&web_location=333.1007&qrcode_key=' +
      qrcodeKey;
  let resp: ApiResponse = await loginHttpGet(url);

  // 重要：根 code 永远是 0（HTTP 层面），二维码实际状态在 data.code 中
  let actualCode: number = 86101; // 默认：未扫码
  console.log("[Login]poll获得数据：resp.data=" + JSON.stringify(resp.data))
  if (resp.data) {
    let dataObj: Record<string, Object> = resp.data as Record<string, Object>;
    console.log("[Login]resp.data：" + dataObj)
    actualCode = (dataObj['code'] as number) ?? 86101;
  }

  let result: PollResult = {
    code: actualCode,
    message: resp.message || '',
    data: null
  };

  // 登录成功（actualCode === 0）时保留 data 以提取 cookies
  if (actualCode === 0 && resp.data) {
    result.data = resp.data;
  }

  return result;
}

/**
 * 从成功的登录轮询响应中提取 cookies
 *
 */
export function saveLoginCookies(data: Object): void {
  let dataObj: Record<string, Object> = data as Record<string, Object>;
  console.info('[Login] saveLoginCookies 收到数据, 字段: ' + JSON.stringify(data));

  // 保存 refresh_token（独立存储，用于后续 cookie 刷新）
  let refreshToken: string = (dataObj['refresh_token'] as string) || '';
  if (refreshToken) {
    cookieMap['refresh_token'] = refreshToken;
    cookiesApiPut('refresh_token', refreshToken);
    AppStorage.set<string>('refresh_token', refreshToken);
    console.info('[Login] refresh_token 已保存: ' + refreshToken.substring(0, 8) + '...');
  } else {
    console.warn('[Login] 响应中无 refresh_token');
  }

  // 跳过 data.cookie_info.cookies[]：该字段返回的是游戏侧 Cookie，
  // 真实的 B 站登录 Cookie 已在 HTTP 请求过程中通过 Set-Cookie
  // 响应头由 extractCookiesFromHeaders() 自动提取并写入 cookieMap。
  // 此处直接基于当前 cookieMap 中的内容做持久化。

  rebuildCookieHeader();
  saveToAppStorage();
  saveLoginData();
  cookiesApiSave();

  console.info('[Login] Cookies saved (from Set-Cookie):', Object.keys(cookieMap).join(', '));
}

/** 将当前 cookieMap 持久化到 AppStorage */
function saveToAppStorage(): void {
  let jsonStr: string = JSON.stringify(cookieMap);
  AppStorage.set<string>('AccountData', jsonStr);
}

/**
 * 登录成功后：将中关键信息(mid/csrf)单独存储
 */
function saveLoginData(): void {
  // DedeUserID → mid
  let dede: string = cookieMap['DedeUserID'] || '';
  if (dede) {
    AppStorage.set<string>('mid', dede);
  }

  // bili_jct → csrf
  let biliJct: string = cookieMap['bili_jct'] || '';
  if (biliJct) {
    AppStorage.set<string>('csrf', biliJct);
  }

  // SESSDATA（登录态核心凭证）
  let sessdata: string = cookieMap['SESSDATA'] || '';
  if (sessdata) {
    AppStorage.set<string>('SESSDATA', sessdata);
  }

  console.info('[Login] saveLoginData: mid=' + dede + ' csrf=' + (biliJct ? '***' : '(empty)'));
}

/**
 * SSO 扩散：登录后向 B 站各子域同步 Cookie
 */
export async function requestSSOs(): Promise<void> {
  let csrf: string = cookieMap['bili_jct'] || '';
  if (!csrf) {
    console.warn('[Login] requestSSOs: 无 csrf token，跳过');
    return;
  }

  try {
    // 1. 获取 SSO 域名列表
    let listUrl: string = 'https://passport.bilibili.com/x/passport-login/web/sso/list';
    let listResp: ApiResponse = await loginHttpPostForm(listUrl, 'csrf=' + encodeURIComponent(csrf));

    // 2. 遍历每个 SSO URL 并 POST
    if (listResp.data) {
      let dataObj: Record<string, Object> = listResp.data as Record<string, Object>;
      let ssoArr: Object[] | undefined = dataObj['sso'] as Object[] | undefined;
      if (ssoArr) {
        console.info('[Login] SSO 扩散: 发现 ' + ssoArr.length + ' 个域名');
        for (let i: number = 0; i < ssoArr.length; i++) {
          let ssoUrl: string = ssoArr[i] as string;
          if (ssoUrl) {
            try {
              await loginHttpPost(ssoUrl);
            } catch (e2) {
              console.warn('[Login] SSO 扩散失败: ' + ssoUrl);
            }
          }
        }
        console.info('[Login] SSO 扩散完成');
      }
    }
  } catch (e) {
    console.warn('[Login] requestSSOs 整体失败:', JSON.stringify(e));
  }
}

/** 从 AppStorage 恢复 cookieMap（应用启动时调用，同时恢复 CookiesApi） */
export function restoreCookiesFromStorage(): void {
  let stored: string | undefined = AppStorage.get<string>('AccountData');
  if (stored) {
    try {
      let parsed: Record<string, string> = JSON.parse(stored) as Record<string, string>;
      let parsedKeys: string[] = Object.keys(parsed);
      for (let i: number = 0; i < parsedKeys.length; i++) {
        let key: string = parsedKeys[i];
        cookieMap[key] = parsed[key];
        cookiesApiPut(key, parsed[key]);
      }
      rebuildCookieHeader();
      console.info('[Login] Cookies restored:', Object.keys(cookieMap).length, 'items');
    } catch (e) {
      console.warn('[Login] Cookie restore failed');
    }
  }
}

/** 从 Cookie 中提取指定值 */
export function getCookieValue(name: string): string {
  return cookieMap[name] || '';
}

// ===== Cookie 刷新 API =====

/** Cookie 刷新信息 */
export interface CookieRefreshInfo {
  refresh: boolean;
  timestamp: number;
}

/**
 * 查询 B 站服务器是否需要刷新 Cookie
 * GET https://passport.bilibili.com/x/passport-login/web/cookie/info
 */
export async function getCookieRefreshInfo(): Promise<CookieRefreshInfo> {
  let csrf: string = getCookieValue('bili_jct');
  let url: string = 'https://passport.bilibili.com/x/passport-login/web/cookie/info';
  if (csrf) {
    url += '?csrf=' + encodeURIComponent(csrf);
  }
  let resp: ApiResponse = await loginHttpGet(url);
  if (!resp.data) {
    return { refresh: false, timestamp: 0 };
  }
  let dataObj: Record<string, Object> = resp.data as Record<string, Object>;
  return {
    refresh: (dataObj['refresh'] as boolean) ?? false,
    timestamp: (dataObj['timestamp'] as number) ?? 0
  };
}

/**
 * 通过 HTML 页面获取 refresh_csrf
 * 请求 bilibili.com/correspond/1/{correspondPath} 并解析 #1-name 元素
 */
export async function getRefreshCsrf(correspondPath: string): Promise<string> {
  if (!correspondPath) {
    return '';
  }

  let url: string = 'https://www.bilibili.com/correspond/1/' + correspondPath;
  console.info('[Login] url = ' + url)
  return new Promise<string>((resolve, reject) => {
    let req: http.HttpRequest = http.createHttp();
    req.request(url, {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': HEADERS['User-Agent'],
        'Referer': 'https://www.bilibili.com/',
        'Cookie': HEADERS['Cookie']
      },
      connectTimeout: 10000,
      readTimeout: 15000
    }, (err: Error, resp: http.HttpResponse) => {
      req.destroy();
      console.info('[Login] resp = ' + JSON.stringify(resp))
      if (err) {
        console.error('[Login] getRefreshCsrf HTTP 失败:', err.message);
        resolve('');
        return;
      }
      let html: string = (typeof resp.result === 'string') ? resp.result : '';
      if (!html) {
        resolve('');
        return;
      }
      // 简单解析 HTML：查找 id="1-name" 的标签内容
      let match: RegExpMatchArray | null = html.match(/id=[\'"]1-name[\'"][^>]*>([^<]+)<\//i);
      if (match && match[1]) {
        console.info("Login - refresh_crsf(Way 1)")
        resolve(match[1].trim());
      } else {
        // 备选：查找 <xxx id="1-name">内容</xxx>
        let match2: RegExpMatchArray | null = html.match(/id="1-name">([\s\S]*?)<\//i);
        console.info("Login - refresh_crsf(Way 2)")
        resolve(match2 ? match2[1].trim() : '');
      }
    });
  });
}

/**
 * 执行 Cookie 刷新
 */
export async function refreshCookie(refreshCsrf: string): Promise<boolean> {
  if (!refreshCsrf) {
    return false;
  }

  // 优先从 cookieMap 读取（由 restoreCookiesFromStorage 从 AccountData 恢复）
  // 兜底到 AppStorage

  // 从大约2026.1开始，扫码登录极大概率不会返回 refresh_token，原因未知
  // 由于做B站Api收集的项目已被律师函，故不修复登录容易掉的问题
  // 有时间再做手机号登录
  let refreshToken: string = cookieMap['refresh_token'] ||
    AppStorage.get<string>('refresh_token') || '';
  console.log("Login - refreshToken = " + refreshToken)
  if (!refreshToken) {
    console.warn('[Login] refresh_token 为空，cookieMap 中现有 key: ' + Object.keys(cookieMap).join(', '));
    return false;
  }

  // 读取当前 cookies 备份
  let cookiesOld: string = HEADERS['Cookie'];

  try {
    // 1. 请求新的 Cookie
    let biliJct: string = cookieMap['bili_jct'] || '';
    let formData: string = 'csrf=' + encodeURIComponent(biliJct) +
      '&refresh_csrf=' + encodeURIComponent(refreshCsrf) +
      '&source=main_web&refresh_token=' + encodeURIComponent(refreshToken);

    let refreshUrl: string = 'https://passport.bilibili.com/x/passport-login/web/cookie/refresh';
    let resp: ApiResponse = await loginHttpPostForm(refreshUrl, formData);

    if (resp.code !== 0) {
      console.error('[Login] Cookie 刷新失败, code=' + resp.code);
      return false;
    }

    // 提取新的 refresh_token
    let refreshTokenNew: string = '';
    if (resp.data) {
      let dataObj: Record<string, Object> = resp.data as Record<string, Object>;
      refreshTokenNew = (dataObj['refresh_token'] as string) || '';
    }

    // 刷新
    let newBiliJct: string = cookieMap['bili_jct'] || '';
    let confirmData: string = 'csrf=' + encodeURIComponent(newBiliJct) +
      '&refresh_token=' + encodeURIComponent(refreshToken);
    let confirmUrl: string = 'https://passport.bilibili.com/x/passport-login/web/confirm/refresh';
    let confirmResp: ApiResponse = await loginHttpPostForm(confirmUrl, confirmData);

    if (confirmResp.code !== 0) {
      console.error('[Login] 确认刷新失败, code=' + confirmResp.code);
      return false;
    }

    // 3. 保存新的 refresh_token（同步到 CookiesApi）
    if (refreshTokenNew) {
      AppStorage.set<string>('refresh_token', refreshTokenNew);
      cookieMap['refresh_token'] = refreshTokenNew;
      cookiesApiPut('refresh_token', refreshTokenNew);
      saveToAppStorage();
    }

    // 更新 mid 和 csrf
    let dede: string = cookieMap['DedeUserID'] || '';
    if (dede) {
      AppStorage.set<string>('mid', dede);
    }
    let biliJctNew: string = cookieMap['bili_jct'] || '';
    if (biliJctNew) {
      AppStorage.set<string>('csrf', biliJctNew);
    }

    // 持久化（LoginApi + CookiesApi）
    saveToAppStorage();
    cookiesApiSave();

    console.info('[Login] Cookie 刷新成功');
    return true;
  } catch (e) {
    console.error('[Login] refreshCookie 异常:', JSON.stringify(e));
    return false;
  }
}

/**
 * 完整 Cookie 刷新检查 + 执行
 * 应用启动时调用：向 B 站服务器询问是否需要刷新，如需则自动执行
 * @returns true=已刷新, false=无需刷新或刷新失败
 */
export async function checkCookieRefreshIfNeeded(): Promise<boolean> {
  try {
    let info: CookieRefreshInfo = await getCookieRefreshInfo();
    if (!info.refresh) {
      console.info('[Login] 服务器指示无需刷新 Cookie');
      return false;
    }

    console.info('[Login] 服务器指示需要刷新 Cookie，开始刷新流程...');
    let timestamp: number = Date.now();
    let correspondPath: string = await getCorrespondPath(timestamp);
    if (!correspondPath) {
      console.error('[Login] 生成 correspondPath 失败');
      return false;
    }

    let refreshCsrf: string = await getRefreshCsrf(correspondPath);
    console.log("Login - refreshCsrf = " + refreshCsrf)
    if (!refreshCsrf) {
      console.error('[Login] 获取 refresh_csrf 失败');
      return false;
    }

    return await refreshCookie(refreshCsrf);
  } catch (e) {
    console.error('[Login] checkCookieRefreshIfNeeded 异常:', JSON.stringify(e));
    return false;
  }
}

/**
 * checkLoginStatus() 返回值：
 *   VALID   — 服务端确认登录有效
 *   INVALID — 登录已失效（未登录/登录过期），应提示用户重新登录
 *   ERROR   — 网络/服务端异常，无法判断登录状态，应保留凭据
 */
export enum LoginCheckStatus {
  VALID,
  INVALID,
  ERROR
}

/**
 * 检查当前登录状态是否有效
 * 调用 B 站 nav API 确认服务端登录态
 * @returns VALID=登录有效, INVALID=已失效/未登录, ERROR=网络/服务端异常
 */
export async function checkLoginStatus(): Promise<LoginCheckStatus> {
  try {
    // 快速本地检查：SESSDATA 是否存在
    if (!cookieMap['SESSDATA'] && !cookieMap['AccountData']) {
      console.info('[Login] 本地无登录凭证');
      return LoginCheckStatus.INVALID;
    }

    // 服务端校验：调用 nav 接口
    let url: string = 'https://api.bilibili.com/x/web-interface/nav';
    let resp: ApiResponse = await loginHttpGet(url);

    console.info("[Login] nav-resp = " + JSON.stringify(resp));
    if (resp.code !== 0 || !resp.data) {
      console.warn('[Login] nav 接口异常, code=' + resp.code);
      return LoginCheckStatus.ERROR;
    }

    let dataObj: Record<string, Object> = resp.data as Record<string, Object>;
    let isLogin: boolean = (dataObj['isLogin'] as boolean) ?? false;

    console.info('[Login] 登录状态检查: isLogin=' + isLogin);
    return isLogin ? LoginCheckStatus.VALID : LoginCheckStatus.INVALID;
  } catch (e) {
    console.error('[Login] checkLoginStatus 网络异常:', JSON.stringify(e));
    return LoginCheckStatus.ERROR;
  }
}

// ===== 获取我的信息 =====

/** 我的账户信息 */
export interface MyAccountInfo {
  mid: number; // 我的 mid
  uname: string; // 我的昵称
  userid: string; // 我的用户名（如 "bili_xxxx"）
  sign: string; // 我的签名
  birthday: string; // 生日 YYYY-MM-DD
  sex: string; // 性别：男 女 保密
  nick_free: boolean; // 是否未设置昵称
  rank: string; // 会员等级
}

/**
 * 获取当前登录用户的 mid、昵称等信息
 * GET https://api.bilibili.com/x/member/web/account
 *
 * @returns 登录成功返回 MyAccountInfo，失败/未登录返回 null
 *
 * 使用示例：
 * ```typescript
 * let info = await getMyAccountInfo();
 * if (info) {
 *   console.info('我的 mid=' + info.mid + ' 昵称=' + info.uname);
 * }
 * ```
 */
export async function getMyAccountInfo(): Promise<MyAccountInfo | null> {
  try {
    // 本地快速检查：没有 SESSDATA 就不用发请求了
    if (!cookieMap['SESSDATA']) {
      console.warn('[Account] 无 SESSDATA，未登录');
      return null;
    }

    let url: string = 'https://api.bilibili.com/x/member/web/account';
    let resp: ApiResponse = await loginHttpGet(url);

    if (resp.code !== 0) {
      console.warn('[Account] 获取信息失败, code=' + resp.code + ' msg=' + resp.message);
      return null;
    }

    if (!resp.data) {
      console.warn('[Account] 返回数据为空');
      return null;
    }

    let d: Record<string, Object> = resp.data as Record<string, Object>;

    let info: MyAccountInfo = {
      mid: (d['mid'] as number) ?? 0,
      uname: (d['uname'] as string) ?? '',
      userid: (d['userid'] as string) ?? '',
      sign: (d['sign'] as string) ?? '',
      birthday: (d['birthday'] as string) ?? '',
      sex: (d['sex'] as string) ?? '',
      nick_free: (d['nick_free'] as boolean) ?? false,
      rank: (d['rank'] as string) ?? ''
    };

    console.info('[Account] 获取成功: mid=' + info.mid + ' uname=' + info.uname);
    return info;
  } catch (e) {
    console.error('[Account] 获取信息异常:', JSON.stringify(e));
    return null;
  }
}

