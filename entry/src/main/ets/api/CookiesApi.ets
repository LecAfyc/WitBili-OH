/**
 * Bilibili Cookie 生成与管理 API
 *
 * 功能：
 *   - checkCookies()：完整检查并生成所有必须的 Cookie
 *   - genBiliTicket()：HMAC-SHA256 签名 + API 调用生成 bili_ticket
 *   - genCookiePayload()：ExClimbWuzhi 验证 payload（浏览器指纹）
 *   - gen_buvid_fp()：完整 MurmurHash3 x64 128-bit 实现（替代简化版 MD5）
 *   - getBuvid3Only() / getWebBuvids()：通过 B 站 API 获取 buvid3/buvid4
 *
 * 与 CommonApi 的集成：
 *   CommonApi 的 httpGet/httpPost 每次请求前会自动调用 getCookieString()
 *   将本模块生成的 Cookie 注入请求头，无需手动处理。
 */

import { http } from '@kit.NetworkKit';
import { hmacSha256, genBuvidFp } from './CommonApi';

// ===== Cookie 存储器 =====

/**
 * 全局 Cookie 存储，键值均为 string
 * 在 App 启动时通过 restoreCookies() 从持久化存储恢复
 */
export let cookieMap: Record<string, string> = {};

/**
 * 获取完整 Cookie 请求头字符串，如：
 *   "_uuid=...; buvid3=...; b_nut=..."
 */
export function getCookieString(): string {
  let parts: string[] = [];
  let keys: string[] = Object.keys(cookieMap);
  for (let i: number = 0; i < keys.length; i++) {
    parts.push(keys[i] + '=' + cookieMap[keys[i]]);
  }
  return parts.join('; ');
}

/** 获取单个 Cookie 值 */
export function getCookieValue(name: string): string {
  return cookieMap[name] || '';
}

/** 写入或覆盖单个 Cookie */
export function putCookie(name: string, value: string): void {
  if (value) {
    cookieMap[name] = value;
  }
}

/** 持久化到 AppStorage */
export function saveToStorage(): void {
  let jsonStr: string = JSON.stringify(cookieMap);
  AppStorage.set<string>('CookiesApi_Data', jsonStr);
}

/** 从 AppStorage 恢复 CookieMap（应用启动时调用） */
export function restoreCookies(): void {
  let stored: string | undefined = AppStorage.get<string>('CookiesApi_Data');
  if (stored) {
    try {
      let parsed: Record<string, string> = JSON.parse(stored) as Record<string, string>;
      let parsedKeys: string[] = Object.keys(parsed);
      for (let i: number = 0; i < parsedKeys.length; i++) {
        let key: string = parsedKeys[i];
        cookieMap[key] = parsed[key];
      }
      console.info('[CookiesApi] 从存储恢复 ' + Object.keys(cookieMap).length + ' 个 Cookie');
    } catch (e) {
      console.warn('[CookiesApi] 恢复失败:', JSON.stringify(e));
    }
  }
}

// ===== 常量 =====

const CHARSET: string = '0123456789ABCDEF';
const MP: string[] = [
  '1', '2', '3', '4', '5', '6', '7', '8', '9',
  'A', 'B', 'C', 'D', 'E', 'F', '10'
];
const PCK: number[] = [8, 4, 4, 4, 12];

/** 其他固定 Cookie（浏览器特征） */
const OTHER_COOKIE_MAP: Record<string, string> = {
  'enable_web_push': 'DISABLE',
  'header_theme_version': 'undefined',
  'home_feed_column': '4',
  'PVID': '1'
};

// ===== Web 风格请求头 =====

/**
 * 生成 Web 风格的 HTTP 请求头列表
 * 用于 Cookie API 的内部 HTTP 调用
 */
export function genWebHeaders(): Record<string, string> {
  return {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.95 Safari/537.36',
    "sec-ch-ua": '"Not=A?Brand";v="99", "Microsoft Edge";v="151", "Chromium";v="151"',
    'Referer': 'https://www.bilibili.com/',
    'Origin': 'https://www.bilibili.com',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9',
    'Sec-Fetch-Site': 'same-site',
    'Sec-Fetch-Mode': 'cors',
    'Sec-Fetch-Dest': 'empty'
  };
}

// ===== ExClimbWuzhi (Cookie 激活) =====

/**
 * 调用 ExClimbWuzhi API 激活 Cookies
 *
 * B 站自己会请求两次，所以这里也请求两次
 * payload 的细节是模拟浏览器指纹，数值是固定的 dummy 数据
 */
export async function activeCookieInfo(): Promise<number> {
  let url: string = 'https://api.bilibili.com/x/internal/gaia-gateway/ExClimbWuzhi';
  let payload: string = genCookiePayload();
  let headers: Record<string, string> = genWebHeaders();
  headers['Content-Type'] = 'application/json; charset=UTF-8';
  headers['Cookie'] = getCookieString();

  try {
    // B站请求两次
    await rawPostJson(url, payload, headers);
    let resp2: Record<string, Object> = await rawPostJson(url, payload, headers);
    let code: number = (resp2['code'] as number) ?? -1;
    return code;
  } catch (e) {
    console.warn('[CookiesApi] activeCookieInfo 失败:', JSON.stringify(e));
    return -1;
  }
}

/**
 * 生成 ExClimbWuzhi 的 payload（浏览器指纹 JSON）
 */
export function genCookiePayload(): string {
  // ArkTS 禁止未类型化的复杂嵌套对象字面量，用字符串拼接构建 payload 避免此限制
  let resolution: [number, number] = genBrowserResolution();
  let uuid: string = getCookieValue('_uuid');
  let ua: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.95 Safari/537.36';
  let w: number = resolution[0];
  let h: number = resolution[1];

  let innerPayload: string = '{'
    + '"5062":' + Date.now() + ','
    + '"39c8":"333.1007.fp.risk",'
    + '"920b":"0",'
    + '"df35":' + JSON.stringify(uuid) + ','
    + '"03bf":"https://www.bilibili.com/",'
    + '"6e7c":"' + w + 'x' + h + '",'
    + '"3c43":{'
    + '"2673":0,'
    + '"5766":24,'
    + '"6527":0,'
    + '"7003":1,'
    + '"807e":1,'
    + '"b8ce":' + JSON.stringify(ua) + ','
    + '"641c":0,'
    + '"07a4":"zh-CN",'
    + '"1c57":8,'
    + '"0bd0":4,'
    + '"748e":[' + h + ',' + w + '],'
    + '"d61f":[' + h + ',' + w + '],'
    + '"fc9d":-480,'
    + '"6aa9":"Asia/Shanghai",'
    + '"75b8":1,'
    + '"3b21":1,'
    + '"8a1c":0,'
    + '"d52f":"not available",'
    + '"adca":"Win32",'
    + '"80c9":' + genPluginArrayJson() + ','
    + '"13ab":"hwAAAABJRU5ErkJggg==",'
    + '"bfe9":"SAAskoALCSsZpEUcC+Av8DxpQVtSPLlMwAAAAASUVORK5CYII=",'
    + '"a3c1":' + genWebglInfoJson() + ','
    +
    '"6bc5":"Google Inc. (Intel)~ANGLE (Intel, Intel(R) HD Graphics 4000 (0x00000166) Direct3D11 vs_5_0 ps_5_0, D3D11)",'
    + '"ed31":0,'
    + '"72bd":0,'
    + '"097b":0,'
    + '"52cd":[0,0,0],'
    + '"a658":' + genFontListJson() + ','
    + '"d02f":"124.04347527516074"'
    + '}'
    + '}';

  return '{"payload":' + JSON.stringify(innerPayload) + '}';
}

function genPluginArrayJson(): string {
  // ArkTS 禁止未类型化的复杂嵌套对象字面量，以 JSON 字符串替代
  let s: string = '['
    + '["360SoftMgrPlugin","360SoftMgrPlugin",[["application/360softmgrplugin","dll"]]],'
    + '["Alipay Security Control 3","Alipay Security Control",[["application/x-alisecctrl-plugin","*"]]],'
    + '["Alipay security control","npaliedit",[["application/aliedit",""]]],'
    + '["BaiduYunGuanjia Application","YunWebDetect",[["application/bd-npyunwebdetect-plugin",""]]],'
    + '["Chromium PDF Plugin","Portable Document Format",[["application/x-google-chrome-pdf","pdf"]]],'
    + '["Chromium PDF Viewer","",[["application/pdf","pdf"]]],'
    +
    '["Java Deployment Toolkit 8.0.2910.10","NPRuntime Script Plug-in Library for Java(TM) Deploy",[["application/java-deployment-toolkit",""]]],'
    + '["Java(TM) Platform SE 8 U291","Next Generation Java Plug-in 11.291.2 for Mozilla browsers",['
    + '["application/x-java-applet",""],["application/x-java-bean",""],'
    + '["application/x-java-vm",""],["application/x-java-applet;version=1.1.1",""],'
    + '["application/x-java-bean;version=1.1.1",""],["application/x-java-applet;version=1.1",""],'
    + '["application/x-java-bean;version=1.1",""],["application/x-java-applet;version=1.2",""],'
    + '["application/x-java-bean;version=1.2",""],["application/x-java-applet;version=1.1.3",""],'
    + '["application/x-java-bean;version=1.1.3",""],["application/x-java-applet;version=1.1.2",""],'
    + '["application/x-java-bean;version=1.1.2",""],["application/x-java-applet;version=1.3",""],'
    + '["application/x-java-bean;version=1.3",""],["application/x-java-applet;version=1.2.2",""],'
    + '["application/x-java-bean;version=1.2.2",""],["application/x-java-applet;version=1.2.1",""],'
    + '["application/x-java-bean;version=1.2.1",""],["application/x-java-applet;version=1.3.1",""],'
    + '["application/x-java-bean;version=1.3.1",""],["application/x-java-applet;version=1.4",""],'
    + '["application/x-java-bean;version=1.4",""],["application/x-java-applet;version=1.4.1",""],'
    + '["application/x-java-bean;version=1.4.1",""],["application/x-java-applet;version=1.4.2",""],'
    + '["application/x-java-bean;version=1.4.2",""],["application/x-java-applet;version=1.5",""],'
    + '["application/x-java-bean;version=1.5",""],["application/x-java-applet;version=1.6",""],'
    + '["application/x-java-bean;version=1.6",""],["application/x-java-applet;version=1.7",""],'
    + '["application/x-java-bean;version=1.7",""],["application/x-java-applet;version=1.8",""],'
    + '["application/x-java-bean;version=1.8",""],["application/x-java-applet;jpi-version=1.8.0_291",""],'
    + '["application/x-java-bean;jpi-version=1.8.0_291",""],["application/x-java-vm-npruntime",""],'
    + '["application/x-java-applet;deploy=11.291.2",""],["application/x-java-applet;javafx=8.0.291",""]]],'
    + '["Microsoft® Windows Media Player Firefox Plugin","np-mswmp",['
    + '["application/x-ms-wmp","*"],["application/asx","*"],'
    + '["video/x-ms-asf-plugin","*"],["application/x-mplayer2","*"],'
    + '["video/x-ms-asf","asf,asx,*"],["video/x-ms-wm","wm,*"],'
    + '["audio/x-ms-wma","wma,*"],["audio/x-ms-wax","wax,*"],'
    + '["video/x-ms-wmv","wmv,*"],["video/x-ms-wvx","wvx,*"]]],'
    + '["QQÒôÀÖ²¥·Å¿Ø¼þ","QQÒôÀÖ²¥·Å¿Ø¼þ",[["application/tecent-qzonemusic-plugin","rts"]]],'
    +
    '["Shockwave Flash","Shockwave Flash 34.0 r0",[["application/x-shockwave-flash","swf"],["application/futuresplash","spl"]]],'
    + '["XunLei User Plugin","Xunlei User scriptability Plugin,version= 2.0.2.3",[["application/npxluser_plugin",""]]],'
    + '["iTrusChina iTrusPTA,XEnroll,iEnroll,hwPTA,UKeyInstalls Firefox Plugin",'
    + '"iTrusPTA&XEnroll hwPTA,IEnroll,UKeyInstalls for FireFox,version=1.0.0.2",'
    + '[["application/pta.itruspta.version.1","*"],["application/cenroll.cenroll.version.1",""],'
    + '["application/itrusenroll.certenroll.version.1",""],["application/hwpta.itrushwpta",""],'
    + '["application/hwwdkey.installwdkey",""],["application/hwepass2001.installepass2001",""]]],'
    + '["npQQPhotoDrawEx","npQQPhotoDrawEx Module",[["application/tencent-qqphotodrawex2-plugin","rts"]]]'
    + ']';
  return s;
}

/** WebGL 信息 JSON 数组字符串 */
function genWebglInfoJson(): string {
  let arr: string[] = [
    'extensions:ANGLE_instanced_arrays;EXT_blend_minmax;EXT_clip_control;EXT_color_buffer_half_float;'
      + 'EXT_depth_clamp;EXT_disjoint_timer_query;EXT_float_blend;EXT_frag_depth;EXT_polygon_offset_clamp;'
      + 'EXT_shader_texture_lod;EXT_texture_compression_bptc;EXT_texture_compression_rgtc;'
      + 'EXT_texture_filter_anisotropic;EXT_sRGB;KHR_parallel_shader_compile;OES_element_index_uint;'
      + 'OES_fbo_render_mipmap;OES_standard_derivatives;OES_texture_float;OES_texture_float_linear;'
      + 'OES_texture_half_float;OES_texture_half_float_linear;OES_vertex_array_object;'
      + 'WEBGL_blend_func_extended;WEBGL_color_buffer_float;WEBGL_compressed_texture_s3tc;'
      + 'WEBGL_compressed_texture_s3tc_srgb;WEBGL_debug_renderer_info;WEBGL_debug_shaders;'
      + 'WEBGL_depth_texture;WEBGL_draw_buffers;WEBGL_lose_context;WEBGL_multi_draw;WEBGL_polygon_mode',
    'webgl aliased line width range:[1, 1]',
    'webgl aliased point size range:[1, 1024]',
    'webgl alpha bits:8',
    'webgl antialiasing:yes',
    'webgl blue bits:8',
    'webgl depth bits:24',
    'webgl green bits:8',
    'webgl max anisotropy:16',
    'webgl max combined texture image units:32',
    'webgl max cube map texture size:16384',
    'webgl max fragment uniform vectors:1024',
    'webgl max render buffer size:16384',
    'webgl max texture image units:16',
    'webgl max texture size:16384',
    'webgl max varying vectors:30',
    'webgl max vertex attribs:16',
    'webgl max vertex texture image units:16',
    'webgl max vertex uniform vectors:4096',
    'webgl max viewport dims:[32767, 32767]',
    'webgl red bits:8',
    'webgl renderer:WebKit WebGL',
    'webgl shading language version:WebGL GLSL ES 1.0 (OpenGL ES GLSL ES 1.0 Chromium)',
    'webgl stencil bits:0',
    'webgl vendor:WebKit',
    'webgl version:WebGL 1.0 (OpenGL ES 2.0 Chromium)',
    'webgl unmasked vendor:Google Inc. (Intel)',
    'webgl unmasked renderer:ANGLE (Intel, Intel(R) HD Graphics 4000 (0x00000166) Direct3D11 vs_5_0 ps_5_0, D3D11)',
    'webgl vertex shader high float precision:23',
    'webgl vertex shader high float precision rangeMin:127',
    'webgl vertex shader high float precision rangeMax:127',
    'webgl vertex shader medium float precision:23',
    'webgl vertex shader medium float precision rangeMin:127',
    'webgl vertex shader medium float precision rangeMax:127',
    'webgl vertex shader low float precision:23',
    'webgl vertex shader low float precision rangeMin:127',
    'webgl vertex shader low float precision rangeMax:127',
    'webgl fragment shader high float precision:23',
    'webgl fragment shader high float precision rangeMin:127',
    'webgl fragment shader high float precision rangeMax:127',
    'webgl fragment shader medium float precision:23',
    'webgl fragment shader medium float precision rangeMin:127',
    'webgl fragment shader medium float precision rangeMax:127',
    'webgl fragment shader low float precision:23',
    'webgl fragment shader low float precision rangeMin:127',
    'webgl fragment shader low float precision rangeMax:127',
    'webgl vertex shader high int precision:0',
    'webgl vertex shader high int precision rangeMin:31',
    'webgl vertex shader high int precision rangeMax:30',
    'webgl vertex shader medium int precision:0',
    'webgl vertex shader medium int precision rangeMin:31',
    'webgl vertex shader medium int precision rangeMax:30',
    'webgl vertex shader low int precision:0',
    'webgl vertex shader low int precision rangeMin:31',
    'webgl vertex shader low int precision rangeMax:30',
    'webgl fragment shader high int precision:0',
    'webgl fragment shader high int precision rangeMin:31',
    'webgl fragment shader high int precision rangeMax:30',
    'webgl fragment shader medium int precision:0',
    'webgl fragment shader medium int precision rangeMin:31',
    'webgl fragment shader medium int precision rangeMax:30',
    'webgl fragment shader low int precision:0',
    'webgl fragment shader low int precision rangeMin:31',
    'webgl fragment shader low int precision rangeMax:30'
  ];
  let combined: string = '';
  for (let i: number = 0; i < arr.length; i++) {
    if (i > 0) {
      combined += ',';
    }
    combined += JSON.stringify(arr[i]);
  }
  return '[' + combined + ']';
}

/** 字体列表 JSON 数组字符串 */
function genFontListJson(): string {
  let arr: string[] = [
    'Arial', 'Arial Black', 'Arial Narrow', 'Arial Unicode MS',
    'Book Antiqua', 'Bookman Old Style', 'Calibri', 'Cambria',
    'Cambria Math', 'Century', 'Century Gothic', 'Century Schoolbook',
    'Comic Sans MS', 'Consolas', 'Courier', 'Courier New',
    'Georgia', 'Helvetica', 'Impact', 'Lucida Bright',
    'Lucida Calligraphy', 'Lucida Console', 'Lucida Fax', 'Lucida Handwriting',
    'Lucida Sans', 'Lucida Sans Typewriter', 'Lucida Sans Unicode',
    'Microsoft Sans Serif', 'Monotype Corsiva', 'MS Gothic', 'MS PGothic',
    'MS Reference Sans Serif', 'MS Sans Serif', 'MS Serif', 'MYRIAD PRO',
    'Palatino Linotype', 'Segoe Print', 'Segoe Script', 'Segoe UI',
    'Segoe UI Light', 'Segoe UI Semibold', 'Segoe UI Symbol',
    'Tahoma', 'Times', 'Times New Roman', 'Trebuchet MS',
    'Verdana', 'Wingdings', 'Wingdings 2', 'Wingdings 3'
  ];
  let combined: string = '';
  for (let i: number = 0; i < arr.length; i++) {
    if (i > 0) {
      combined += ',';
    }
    combined += JSON.stringify(arr[i]);
  }
  return '[' + combined + ']';
}

// ===== 原始 HTTP 请求工具（CookiesApi 内部使用，避免与 CommonApi 循环依赖） =====

/**
 * 发送 POST JSON 请求，返回解析后的对象
 */
function rawPostJson(url: string, jsonBody: string, headers: Record<string, string>): Promise<Record<string, Object>> {
  return new Promise<Record<string, Object>>((resolve, reject) => {
    let req: http.HttpRequest = http.createHttp();
    req.request(url, {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: jsonBody,
      connectTimeout: 10000,
      readTimeout: 15000
    }, (err: Error, resp: http.HttpResponse) => {
      req.destroy();
      if (err) {
        reject(new Error(err.message));
        return;
      }
      let result: Object = resp.result;
      if (typeof result === 'string' && result) {
        try {
          resolve(JSON.parse(result) as Record<string, Object>);
        } catch (e) {
          reject(new Error('JSON parse error'));
        }
      } else if (typeof result === 'object' && result !== null) {
        resolve(result as Record<string, Object>);
      } else {
        reject(new Error('Empty response'));
      }
    });
  });
}

/**
 * 发送 GET 请求，返回解析后的 JSON 对象
 */
function rawGetJson(url: string, headers: Record<string, string>): Promise<Record<string, Object>> {
  return new Promise<Record<string, Object>>((resolve, reject) => {
    let req: http.HttpRequest = http.createHttp();
    req.request(url, {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: 10000,
      readTimeout: 15000
    }, (err: Error, resp: http.HttpResponse) => {
      req.destroy();
      if (err) {
        reject(new Error(err.message));
        return;
      }
      let result: Object = resp.result;
      if (typeof result === 'string' && result) {
        try {
          resolve(JSON.parse(result) as Record<string, Object>);
        } catch (e) {
          reject(new Error('JSON parse error'));
        }
      } else if (typeof result === 'object' && result !== null) {
        resolve(result as Record<string, Object>);
      } else {
        reject(new Error('Empty response'));
      }
    });
  });
}

/**
 * POST 空 body 请求（参数全部在 URL query string 中），不自动添加 Content-Type
 * 用于 genBiliTicket：B 站接口对于空 body 的 POST 请求禁止发送 Content-Type
 */
function rawPostNoBody(url: string, headers: Record<string, string>): Promise<Record<string, Object>> {
  return new Promise<Record<string, Object>>((resolve, reject) => {
    let req: http.HttpRequest = http.createHttp();
    req.request(url, {
      method: http.RequestMethod.POST,
      header: headers,
      connectTimeout: 10000,
      readTimeout: 15000
    }, (err: Error, resp: http.HttpResponse) => {
      req.destroy();
      if (err) {
        reject(new Error(err.message));
        return;
      }
      let result: Object = resp.result;
      if (typeof result === 'string' && result) {
        try {
          resolve(JSON.parse(result) as Record<string, Object>);
        } catch (e) {
          reject(new Error('JSON parse error'));
        }
      } else if (typeof result === 'object' && result !== null) {
        resolve(result as Record<string, Object>);
      } else {
        reject(new Error('Empty response'));
      }
    });
  });
}

/**
 * 发送 POST application/x-www-form-urlencoded 请求，返回原始文本结果
 */
function rawPostForm(url: string, formData: string, headers: Record<string, string>): Promise<Record<string, Object>> {
  return new Promise<Record<string, Object>>((resolve, reject) => {
    let req: http.HttpRequest = http.createHttp();
    req.request(url, {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: formData,
      connectTimeout: 10000,
      readTimeout: 15000
    }, (err: Error, resp: http.HttpResponse) => {
      req.destroy();
      if (err) {
        reject(new Error(err.message));
        return;
      }
      let result: Object = resp.result;
      if (typeof result === 'string' && result) {
        try {
          resolve(JSON.parse(result) as Record<string, Object>);
        } catch (e) {
          reject(new Error('JSON parse error'));
        }
      } else if (typeof result === 'object' && result !== null) {
        resolve(result as Record<string, Object>);
      } else {
        reject(new Error('Empty response'));
      }
    });
  });
}

/**
 * GET 请求返回原始 HTML 文本
 */
function rawGetText(url: string, headers: Record<string, string>): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    let req: http.HttpRequest = http.createHttp();
    req.request(url, {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: 10000,
      readTimeout: 15000
    }, (err: Error, resp: http.HttpResponse) => {
      req.destroy();
      if (err) {
        reject(new Error(err.message));
        return;
      }
      resolve((typeof resp.result === 'string') ? resp.result : '');
    });
  });
}

// ===== buvid3 / buvid4 获取 =====

/**
 * 仅获取 buvid3
 * GET https://api.bilibili.com/x/web-frontend/getbuvid
 */
export async function getBuvid3Only(): Promise<string> {
  try {
    let data: Record<string, Object> = await rawGetJson(
      'https://api.bilibili.com/x/web-frontend/getbuvid',
      genWebHeaders()
    );
    return (data['buvid'] as string) || '';
  } catch (e) {
    console.warn('[CookiesApi] getBuvid3Only 失败:', JSON.stringify(e));
    return '';
  }
}

/**
 * 获取 buvid3 和 buvid4
 * GET https://api.bilibili.com/x/frontend/finger/spi
 * @returns [buvid3, buvid4]
 */
export async function getWebBuvids(): Promise<[string, string]> {
  try {
    let resp: Record<string, Object> = await rawGetJson(
      'https://api.bilibili.com/x/frontend/finger/spi',
      genWebHeaders()
    );
    let data: Record<string, Object> = (resp['data'] as Record<string, Object>) || {};
    return [
      (data['b_3'] as string) || '',
      (data['b_4'] as string) || ''
    ];
  } catch (e) {
    console.warn('[CookiesApi] getWebBuvids 失败:', JSON.stringify(e));
    return ['', ''];
  }
}


// ===== bili_ticket 生成

/**
 * 生成 bili_ticket
 * HMAC-SHA256 签名后 POST 到 GenWebTicket API
/** bili_ticket 返回类型 */
export interface TicketResult {
  ticket: string;
  createdAt: number;
}

/**
 * 生成 bili_ticket
 * HMAC-SHA256 签名后 POST 到 GenWebTicket API
 */
export async function genBiliTicket(): Promise<TicketResult> {
  let ts: number = Math.floor(Date.now() / 1000);
  let hexsign: string = hmacSha256('XgwSnGZ1p', 'ts' + ts);
  let csrf: string = getCookieValue('bili_jct') || getCookieValue('csrf') || '';

  console.info("Cookie - 准备数据完成")

  let urlParams: string = 'key_id=ec02'
    + '&hexsign=' + encodeURIComponent(hexsign)
    + '&context%5Bts%5D=' + ts
    + '&csrf=' + encodeURIComponent(csrf);
  let url: string = 'https://api.bilibili.com/bapis/bilibili.api.ticket.v1.Ticket/GenWebTicket?' + urlParams;

  console.info("Cookie - url=" + url)
  try {
    // POST 请求，参数在 URL 中。Body 为空，不设置 Content-Type。
    let headers: Record<string, string> = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.95 Safari/537.36',
      'Referer': 'https://www.bilibili.com/'
    };
    // 使用 rawPostNoBody 发空 body（不在 extraData 中设 body），不设 Content-Type 头
    let result: Record<string, Object> = await rawPostNoBody(url, headers);
    console.info(
      '[CookiesApi] genBiliTicket 响应: code=' + result['code'] + ' hasData=' + (result['data'] !== undefined));
    if (result['data']) {
      let data: Record<string, Object> = result['data'] as Record<string, Object>;
      return { ticket: (data['ticket'] as string) || '', createdAt: (data['created_at'] as number) || 0 };
    }
    return { ticket: '', createdAt: 0 };
  } catch (e) {
    console.warn('[CookiesApi] genBiliTicket 失败:', JSON.stringify(e));
    return { ticket: '', createdAt: 0 };
  }
}


// ===== 本地 Cookie 生成工具 =====

/** 获取浏览器分辨率 */
function genBrowserResolution(): [number, number] {
  return [1920, 1080]; //返回真实的的手表分辨率反而更奇怪吧？？
}

/**
 * 生成 _uuid（格式："XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX-XXXXXinfoc"）
 */
export function genUuid(): string {
  let t: number = Date.now() % 100000;
  let parts: string[] = [];
  for (let pi: number = 0; pi < PCK.length; pi++) {
    let p: number = PCK[pi];
    let s: string = '';
    for (let i: number = 0; i < p; i++) {
      s += MP[Math.floor(Math.random() * 16)];
    }
    parts.push(s);
  }
  return parts.join('-') + String(t).padStart(5, '0') + 'infoc';
}

/** 生成 b_nut（当前 Unix 时间戳，单位为秒） */
export function genBNut(): string {
  return String(Math.floor(Date.now() / 1000));
}

/**
 * 生成 b_lsid（8 位随机十六进制 + "_" + 当前毫秒时间戳十六进制（大写））
 */
export function genBlsid(): string {
  let sb: string = '';
  for (let i: number = 0; i < 8; i++) {
    sb += CHARSET.charAt(Math.floor(Math.random() * CHARSET.length));
  }
  return sb + '_' + Date.now().toString(16).toUpperCase();
}

// ===== checkCookies（完整检查与生成） =====

/**
 * 完整检查并生成所有必须的 B 站 Cookie
 *
 * 生成顺序（与 B 站浏览器请求顺序一致）：
 *   1. 访问 B 站首页获取初始 Cookie
 *   2. _uuid（本地生成）
 *   3. b_nut（本地生成，Unix 秒时间戳）
 *   4. b_lsid（本地生成，随机 hex + 时间戳 hex）
 *   5. buvid3（通过 API 获取）
 *   6. buvid3 + buvid4（通过 finger/spi API 获取）
 *   7. LIVE_BUVID（本地生成）
 *   8. browser_resolution（屏幕分辨率）
 *   9. bili_ticket（HMAC-SHA256 + API）
 *   10. buvid_fp（MurmurHash3 x64 128）
 *   11. 其他固定值（enable_web_push 等）
 *
 * @param loginCookieMap 可选：LoginApi 的 cookieMap，合并其中的登录态 Cookie（SESSDATA 等）
 */
export async function checkCookies(loginCookieMap?: Record<string, string>): Promise<void> {
  console.info('[CookiesApi] checkCookies: 开始检查 Cookie 环境...');

  // 0. 合并 LoginApi 中的现有 Cookie（SESSDATA, DedeUserID, bili_jct 等）
  if (loginCookieMap) {
    let loginKeys: string[] = Object.keys(loginCookieMap);
    for (let i: number = 0; i < loginKeys.length; i++) {
      if (!cookieMap[loginKeys[i]] && loginCookieMap[loginKeys[i]]) {
        cookieMap[loginKeys[i]] = loginCookieMap[loginKeys[i]];
      }
    }
  }

  // 1. 访问 B 站首页，让服务器下发初始 Cookie（buvid3, buvid4 等）
  try {
    let headers: Record<string, string> = genWebHeaders();
    headers['Cookie'] = getCookieString();
    await rawGetText('https://www.bilibili.com/', headers);
  } catch (e) {
    console.warn('[CookiesApi] 首页请求失败（不影响本地生成）:', JSON.stringify(e));
  }

  // 2. _uuid
  if (!cookieMap['_uuid']) {
    cookieMap['_uuid'] = genUuid();
  }

  // 3. b_nut
  if (!cookieMap['b_nut']) {
    cookieMap['b_nut'] = genBNut();
  }

  // 4. b_lsid
  if (!cookieMap['b_lsid']) {
    cookieMap['b_lsid'] = genBlsid();
  }

  // 5. buvid3（单个接口，B 站浏览器顺序是：先获取单个 buvid3）
  if (!cookieMap['buvid3']) {
    let buvid3: string = await getBuvid3Only();
    if (buvid3) {
      cookieMap['buvid3'] = buvid3;
    }
  }

  // 6. buvid3 + buvid4（finger/spi 接口）
  if (!cookieMap['buvid4']) {
    // ArkTS 不支持解构赋值，使用临时变量
    let bv: [string, string] = await getWebBuvids();
    let b3: string = bv[0];
    let b4: string = bv[1];
    if (b3) {
      cookieMap['buvid3'] = b3;
    }
    if (b4) {
      cookieMap['buvid4'] = b4;
    }
  }

  // 7. LIVE_BUVID
  if (!cookieMap['LIVE_BUVID']) {
    let min: number = 1000000000000000;
    let max: number = 9999999999999999;
    cookieMap['LIVE_BUVID'] = 'AUTO' + Math.floor(min + Math.random() * (max - min));
  }

  // 8. browser_resolution
  if (!cookieMap['browser_resolution']) {
    let res: [number, number] = genBrowserResolution();
    cookieMap['browser_resolution'] = res[0] + '-' + res[1];
  }

  // 9. bili_ticket（检查是否过期或缺失）
  let needTicket: boolean = true;
  let ticketExpiresStr: string = cookieMap['bili_ticket_expires'] || '';
  if (cookieMap['bili_ticket'] && cookieMap['bili_ticket'] !== 'null' && ticketExpiresStr) {
    let ticketExpires: number = parseIntSafe(ticketExpiresStr);
    if (ticketExpires > 0 && ticketExpires > Math.floor(Date.now() / 1000)) {
      needTicket = false;
    }
  }
  if (needTicket) {
    try {
      let ticketResult: TicketResult = await genBiliTicket();
      if (ticketResult.ticket) {
        cookieMap['bili_ticket'] = ticketResult.ticket;
        cookieMap['bili_ticket_expires'] = String(ticketResult.createdAt + 3 * 24 * 60 * 60);
        console.info('[CookiesApi] bili_ticket 生成成功');
      }
    } catch (e) {
      console.warn('[CookiesApi] bili_ticket 生成失败:', JSON.stringify(e));
    }
  }

  // 10. buvid_fp（MurmurHash3 x64 128）
  if (!cookieMap['buvid_fp']) {
    let uaPart: string = genWebHeaders()['User-Agent'];
    cookieMap['buvid_fp'] = genBuvidFp(uaPart + Date.now(), 31n);
  }

  // 11. 其他固定值
  let otherKeys: string[] = Object.keys(OTHER_COOKIE_MAP);
  for (let i: number = 0; i < otherKeys.length; i++) {
    let key: string = otherKeys[i];
    if (!cookieMap[key]) {
      cookieMap[key] = OTHER_COOKIE_MAP[key];
    }
  }

  // 持久化
  saveToStorage();
  console.info('[CookiesApi] checkCookies 完成, Cookie 数: ' + Object.keys(cookieMap).length);
}

/** 安全解析整数，非数字返回 0 */
function parseIntSafe(str: string): number {
  try {
    let n: number = parseInt(str);
    return isNaN(n) ? 0 : n;
  } catch (_e) {
    return 0;
  }
}
