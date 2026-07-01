/**
 * 通用工具
 *
 */

import { http } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer } from '@kit.ArkTS';
import { getCookieString } from './CookiesApi';

// ===== 响应类型 =====

export interface ApiResponse {
  code: number;
  message: string;
  data: Object | null;
}

export let HEADERS: Record<string, string> = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Referer': 'https://www.bilibili.com/',
  'Origin': 'https://www.bilibili.com',
  'Accept': 'application/json, text/plain, */*',
  'Accept-Language': 'zh-CN,zh;q=0.9',
  'Cookie': ''
};

// ===== 工具函数 =====

// av/bv 的转换
const XOR_CODE: bigint = BigInt(23442827791579);
const MASK_CODE: bigint = BigInt(2251799813685247);
const MAX_AID: bigint = BigInt(1) << BigInt(51);
const BASE: bigint = BigInt(58);

const data: string = 'FcwAPNKTMug3GV5Lj7EJnHpWsx4tb8haYeviqBz6rkCy12mUSDQX9RdoZf';

export function av2bv(aid: number): string {
  const bytes: string[] = ['B', 'V', '1', '0', '0', '0', '0', '0', '0', '0', '0', '0'];
  let bvIndex: number = bytes.length - 1;
  let tmp: bigint = (MAX_AID | BigInt(aid)) ^ XOR_CODE;
  while (tmp > 0) {
    bytes[bvIndex] = data[Number(tmp % BASE)];
    tmp = tmp / BASE;
    bvIndex -= 1;
  }
  // 交换 bytes[3] 和 bytes[9]
  const temp1: string = bytes[3];
  bytes[3] = bytes[9];
  bytes[9] = temp1;
  // 交换 bytes[4] 和 bytes[7]
  const temp2: string = bytes[4];
  bytes[4] = bytes[7];
  bytes[7] = temp2;
  return bytes.join('');
}

export function bv2av(bvid: string): number {
  const bvidArr: string[] = Array.from(bvid);
  // 交换 bvidArr[3] 和 bvidArr[9]
  const temp1: string = bvidArr[3];
  bvidArr[3] = bvidArr[9];
  bvidArr[9] = temp1;
  // 交换 bvidArr[4] 和 bvidArr[7]
  const temp2: string = bvidArr[4];
  bvidArr[4] = bvidArr[7];
  bvidArr[7] = temp2;
  bvidArr.splice(0, 3);
  const tmp: bigint =
    bvidArr.reduce((pre: bigint, bvidChar: string) => pre * BASE + BigInt(data.indexOf(bvidChar)), BigInt(0));
  return Number((tmp & MASK_CODE) ^ XOR_CODE);
}

/**
 * 安全解析 JSON
 */
export function safeJsonParse(raw: Object | string | number | undefined | null): Record<string, Object> | null {
  if (raw === undefined || raw === null) {
    return null;
  }
  if (typeof raw === 'object') {
    // HarmonyOS 某些版本 http 模块已自动 JSON 解析，resp.result 为 Object
    return raw as Record<string, Object>;
  }
  if (typeof raw !== 'string' || raw.length === 0) {
    return null;
  }
  try {
    return JSON.parse(raw) as Record<string, Object>;
  } catch (e) {
    return null;
  }
}

// ===== HTML 转义符解码 =====

/**
 * 解码 &gt; &lt; &amp; &quot; &#39; &nbsp; 等 HTML 实体
 * 覆盖常见十进制/十六进制实体及 &amp;nbsp;
 */
export function decodeHTML(text: string): string {
  if (!text) {
    return '';
  }
  return text
    .replace(/&gt;/g, '>')
    .replace(/&lt;/g, '<')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#34;/g, '"')
    .replace(/&#38;/g, '&')
    .replace(/&#60;/g, '<')
    .replace(/&#62;/g, '>')
    .replace(/&#x27;/g, "'")
    .replace(/&#x2F;/g, '/')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&');
}

// ===== 数字格式化（万/亿） =====

/**
 * 将数字格式化为 万/亿 显示
 * 示例：12345 → "1.2万"  123456789 → "1.2亿"
 */
export function formatCount(n: number): string {
  if (n >= 100000000) {
    return (n / 100000000).toFixed(1) + '亿';
  }
  if (n >= 10000) {
    return (n / 10000).toFixed(1) + '万';
  }
  return n.toString();
}

// ===== 请求选项 =====

export interface RequestOptions {
  /** 自定义请求头（与默认 HEADERS 合并） */
  headers?: Record<string, string>;

  /** 连接超时（毫秒，默认 10000） */
  connectTimeout?: number;

  /** 读取超时（毫秒，默认 15000） */
  readTimeout?: number;

  /** POST body */
  extraData?: string;

  /** 强制指定 Content-Type */
  contentType?: string;

  /** 响应头回调（如 LoginApi 提取 Cookie） */
  onHeaders?: (headers: Record<string, Object>) => void;

  /** 自定义日志标签（默认 "[HTTP]"） */
  logTag?: string;
}

// ===== 内部工具 =====

/** 复制 Record 的所有键值对（ArkTS 不支持对象 spread） */
function copyRecord(src: Record<string, string>): Record<string, string> {
  let result: Record<string, string> = {};
  let keys: string[] = Object.keys(src);
  for (let i: number = 0; i < keys.length; i++) {
    result[keys[i]] = src[keys[i]];
  }
  return result;
}

function mergeHeaders(base: Record<string, string>, extra?: Record<string, string>,
  contentType?: string): Record<string, string> {
  let result: Record<string, string> = copyRecord(base);
  if (extra) {
    let keys: string[] = Object.keys(extra);
    for (let i: number = 0; i < keys.length; i++) {
      result[keys[i]] = extra[keys[i]];
    }
  }
  if (contentType) {
    result['Content-Type'] = contentType;
  }
  // 以 CookiesApi 为 Cookie 唯一来源覆盖所有请求的 Cookie 头
  // LoginApi 的登录态 Cookie（SESSDATA, DedeUserID, bili_jct 等）已同步到 CookiesApi
  let cookiesApiStr: string = getCookieString();
  if (cookiesApiStr) {
    result['Cookie'] = cookiesApiStr;
  }
  return result;
}

function getLogTag(opts?: RequestOptions): string {
  return opts?.logTag ?? '[HTTP]';
}

function handleResponse(req: http.HttpRequest, url: string, opts: RequestOptions | undefined,
  err: Error, resp: http.HttpResponse, resolve: (value: ApiResponse) => void,
  reject: (reason: Error) => void): void {
  req.destroy();
  let tag: string = getLogTag(opts);

  if (err) {
    console.error(tag + ' 请求失败: url=' + url + ' msg=' + err.message);
    reject(new Error('HTTP: ' + err.message));
    return;
  }

  console.info(tag + ' 完成 url=' + url);

  // 响应头回调（LoginApi 提取 Cookie）
  if (opts?.onHeaders) {
    let respHeaders: Record<string, Object> = (resp.header || {}) as Record<string, Object>;
    opts.onHeaders(respHeaders);
  }

  // 解析 JSON
  let jsonObj: Record<string, Object> | null = safeJsonParse(resp.result);
  if (!jsonObj) {
    let emptyResp: ApiResponse = { code: -1, message: 'empty or non-json response', data: null };
    resolve(emptyResp);
    return;
  }

  let apiResponse: ApiResponse = {
    code: (jsonObj['code'] as number) ?? -1,
    message: (jsonObj['message'] as string) ?? '',
    data: jsonObj['data'] ?? null
  };
  resolve(apiResponse);
}

// ===== HTTP GET =====

export function httpGet(url: string, opts?: RequestOptions): Promise<ApiResponse> {
  return new Promise<ApiResponse>((resolve, reject) => {
    let tag: string = getLogTag(opts);
    console.info(tag + ' GET url=' + url);
    let req: http.HttpRequest = http.createHttp();
    let headers: Record<string, string> = mergeHeaders(HEADERS, opts?.headers, opts?.contentType);

    req.request(url, {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: opts?.connectTimeout ?? 10000,
      readTimeout: opts?.readTimeout ?? 15000
    }, (err: Error, resp: http.HttpResponse) => {
      handleResponse(req, url, opts, err, resp, resolve, reject);
    });
  });
}

//getTest
export function httpTest(url: string, opts?: RequestOptions): Promise<boolean> {
  return new Promise((resolve, reject) => {
    let tag: string = getLogTag(opts);
    console.info(tag + '(Test) GET(Range) url=' + url);

    let req: http.HttpRequest = http.createHttp();
    let headers: Record<string, string> = mergeHeaders(HEADERS, opts?.headers, opts?.contentType);
    // CDN 视频流通常不支持 HEAD，改用 GET + 小范围读取首字节
    headers['Range'] = 'bytes=0-1023';

    req.request(url, {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: opts?.connectTimeout ?? 10000,
      readTimeout: opts?.readTimeout ?? 15000
    }, (err: Error, resp: http.HttpResponse) => {
      req.destroy();
      if (err) {
        console.error(tag + 'Test Result: err = ' + err.message);
        resolve(false);
        return;
      }
      if (!resp) {
        console.error(tag + 'Test Result: resp is undefined');
        resolve(false);
        return;
      }
      const statusCode = resp.responseCode;
      console.info(tag + 'Test Result: statusCode = ' + statusCode);

      // 206 Partial Content 表示 CDN 正常响应
      // 200 也视为成功
      if (statusCode === 206 || (statusCode >= 200 && statusCode < 300)) {
        console.info(tag + 'URL valid');
        resolve(true);
      } else if (statusCode === 403) {
        console.warn(tag + 'URL forbidden (403) - CDN 鉴权失败');
        resolve(false);
      } else if (statusCode === 404) {
        console.warn(tag + 'URL not found (404)');
        resolve(false);
      } else if (statusCode >= 300 && statusCode < 400) {
        console.info(tag + 'URL redirected, status = ' + statusCode);
        resolve(true);
      } else {
        console.warn(tag + 'URL check failed, status = ' + statusCode);
        resolve(false);
      }
    });
  });
}

// ===== HTTP GET 返回原始文本（非 JSON） =====

/**
 * HTTP GET 请求，返回原始文本内容
 *
 * 适用于 XML、HTML、纯文本等非 JSON 响应。
 * HarmonyOS HTTP 库会自动处理 Content-Encoding: gzip / deflate 解压缩。
 *
 * @param url 请求 URL
 * @param opts 可选配置（超时、请求头等）
 */
export function httpGetText(url: string, opts?: RequestOptions): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    let tag: string = getLogTag(opts);
    console.info(tag + ' GET(Text) url=' + url);
    let req: http.HttpRequest = http.createHttp();
    let headers: Record<string, string> = mergeHeaders(HEADERS, opts?.headers, opts?.contentType);

    req.request(url, {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: opts?.connectTimeout ?? 10000,
      readTimeout: opts?.readTimeout ?? 15000,
      // 指定字符串类型让底层自动处理 Content-Encoding 解压缩
      expectDataType: http.HttpDataType.STRING
    }, (err: Error, resp: http.HttpResponse) => {
      req.destroy();

      if (err) {
        console.error(tag + ' 请求失败: url=' + url + ' msg=' + err.message);
        reject(new Error('HTTP: ' + err.message));
        return;
      }

      console.info(tag + ' 完成 url=' + url);

      // 响应头回调
      if (opts?.onHeaders) {
        let respHeaders: Record<string, Object> = (resp.header || {}) as Record<string, Object>;
        opts.onHeaders(respHeaders);
      }

      if (resp.responseCode !== 200) {
        reject(new Error('HTTP ' + resp.responseCode));
        return;
      }

      let rawResult: string = resp.result as string;
      if (rawResult === undefined || rawResult === null || rawResult.length === 0) {
        reject(new Error('响应内容为空'));
        return;
      }

      // 安全检测：检查响应是否仍为 deflate 残留
      // 正常的 XML 应以 '<' 或 '<?' 开头；若以不可打印字符开头说明可能未解压
      let firstChar: string = rawResult.charAt(0);
      let firstByte: number = firstChar.charCodeAt(0);
      if (firstByte !== 0x3C && // '<'
        firstByte < 0x20 && firstByte !== 0x09 && firstByte !== 0x0A && firstByte !== 0x0D) {
        console.warn(tag + ' 响应内容以 0x' + firstByte.toString(16) + ' 开头，可能未正确解压（deflate）');
      }

      resolve(rawResult);
    });
  });
}


// ===== HTTP POST =====

export function httpPost(url: string, opts?: RequestOptions): Promise<ApiResponse> {
  return new Promise<ApiResponse>((resolve, reject) => {
    let tag: string = getLogTag(opts);
    console.info(tag + ' POST url=' + url);
    let req: http.HttpRequest = http.createHttp();
    let headers: Record<string, string> = mergeHeaders(HEADERS, opts?.headers, opts?.contentType);

    let requestOpts: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      connectTimeout: opts?.connectTimeout ?? 10000,
      readTimeout: opts?.readTimeout ?? 15000
    };
    if (opts?.extraData) {
      requestOpts.extraData = opts.extraData;
    }

    req.request(url, requestOpts, (err: Error, resp: http.HttpResponse) => {
      handleResponse(req, url, opts, err, resp, resolve, reject);
    });
  });
}

// ===== HTTP POST Form =====

/**
 * POST 带 application/x-www-form-urlencoded body
 */
export function httpPostForm(url: string, data: string, opts?: RequestOptions): Promise<ApiResponse> {
  let mergedOpts: RequestOptions = {
    extraData: data,
    contentType: 'application/x-www-form-urlencoded',
    connectTimeout: opts?.connectTimeout,
    readTimeout: opts?.readTimeout,
    headers: opts?.headers,
    onHeaders: opts?.onHeaders,
    logTag: opts?.logTag
  };
  return httpPost(url, mergedOpts);
}

// 你遥遥领先的鸿蒙手表没有一个复杂加密算法是系统自带的 👍👍👍👍👍
// 文档里还写支持Wearable给我气笑了 👍👍👍👍👍
// 下面都是纯手写的各种加密，想赤石的可以继续看 😇

interface RsaPubKey {
  n: bigint;
  e: bigint;
}

// RSA 公钥（B 站固定密钥）
const RSA_PUBLIC_KEY_B64: string =
  'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDLgd2OAkcGVtoE3ThUREbio0EgUc/prcajMKXvkCKFCWhJYJcLkcM2DKKcSeFpD/j6Boy538YXnR6VhcuUJOhH2x71nzPjfdTcqMz7djHum0qSZA0AyCBDABUqCrfNgCiJ00Ra7GmRj+YCK1NJEuewlb40JNrRuoEUXpabUzGB8QIDAQAB';

/** base16/hex 编码 */
function base16Encode(src: Uint8Array): string {
  let hex: string = '';
  for (let i: number = 0; i < src.length; i++) {
    let b: number = src[i];
    if ((b & 0xff) < 0x10) {
      hex += '0';
    }
    hex += (b & 0xff).toString(16);
  }
  return hex;
}

/** 跳过 DER TLV 的长度字节，返回内容数据起始位置 */
function skipDerLength(buf: Uint8Array, pos: number): number {
  let len: number = buf[pos];
  if (len < 0x80) {
    return pos + 1;
  }
  let numBytes: number = len & 0x7F;
  return pos + 1 + numBytes;
}

/** 读取 DER 长度值 */
function readDerLength(buf: Uint8Array, pos: number): number {
  let len: number = buf[pos];
  if (len < 0x80) {
    return len;
  }
  let numBytes: number = len & 0x7F;
  let value: number = 0;
  for (let i: number = 1; i <= numBytes; i++) {
    value = (value << 8) + buf[pos + i];
  }
  return value;
}

/** 计算 DER 长度字段占用的字节数 */
function derLengthBytes(buf: Uint8Array, pos: number): number {
  let len: number = buf[pos];
  if (len < 0x80) {
    return 1;
  }
  return 1 + (len & 0x7F);
}

/**
 * 从 DER 编码的 RSA SubjectPublicKeyInfo 中解析 n（模数）和 e（指数）
 */
function parseRsaPubKeyDer(der: Uint8Array): RsaPubKey {
  let i: number = 0;
  // SPKI SEQUENCE
  if (der[i++] !== 0x30) {
    throw new Error('Bad SPKI: expected SEQUENCE');
  }
  i = skipDerLength(der, i);

  // AlgorithmIdentifier SEQUENCE — 跳过整个 TLV
  if (der[i++] !== 0x30) {
    throw new Error('Bad SPKI: expected AlgorithmIdentifier');
  }
  let algLen: number = readDerLength(der, i);
  i += derLengthBytes(der, i) + algLen;

  // BIT STRING
  if (der[i++] !== 0x03) {
    throw new Error('Bad SPKI: expected BIT STRING');
  }
  i += derLengthBytes(der, i) + 1; // +1 跳过 unused bits 字节

  // RSAPublicKey SEQUENCE
  if (der[i++] !== 0x30) {
    throw new Error('Bad RSA key: expected SEQUENCE');
  }
  i = skipDerLength(der, i);

  // INTEGER (modulus n)
  if (der[i++] !== 0x02) {
    throw new Error('Bad RSA key: expected INTEGER');
  }
  let nLen: number = readDerLength(der, i);
  i += derLengthBytes(der, i);
  let n: bigint = 0n;
  for (let j: number = 0; j < nLen; j++) {
    n = (n << 8n) + BigInt(der[i + j]);
  }
  i += nLen;

  // INTEGER (exponent e)
  if (der[i++] !== 0x02) {
    throw new Error('Bad RSA key: expected INTEGER');
  }
  let eLen: number = readDerLength(der, i);
  i += derLengthBytes(der, i);
  let e: bigint = 0n;
  for (let j: number = 0; j < eLen; j++) {
    e = (e << 8n) + BigInt(der[i + j]);
  }
  let result: RsaPubKey = { n: n, e: e };
  return result;
}

/** MGF1 (Mask Generation Function) with SHA-256 */
async function mgf1Sha256(seed: Uint8Array, maskLen: number): Promise<Uint8Array> {
  let result: Uint8Array = new Uint8Array(maskLen);
  let offset: number = 0;
  let counter: number = 0;
  let md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
  while (offset < maskLen) {
    let cntBytes: Uint8Array = new Uint8Array(4);
    cntBytes[0] = (counter >>> 24) & 0xFF;
    cntBytes[1] = (counter >>> 16) & 0xFF;
    cntBytes[2] = (counter >>> 8) & 0xFF;
    cntBytes[3] = counter & 0xFF;
    let combined: Uint8Array = new Uint8Array(seed.length + 4);
    combined.set(seed);
    combined.set(cntBytes, seed.length);
    await md.update({ data: combined } as cryptoFramework.DataBlob);
    let hashData: cryptoFramework.DataBlob = await md.digest();
    md = cryptoFramework.createMd('SHA256');
    let copyLen: number = Math.min(hashData.data.length, maskLen - offset);
    result.set(hashData.data.subarray(0, copyLen), offset);
    offset += copyLen;
    counter++;
  }
  return result;
}

/** 模幂运算（快速幂） */
function modPow(base: bigint, exp: bigint, mod: bigint): bigint {
  if (mod === 1n) {
    return 0n;
  }
  let result: bigint = 1n;
  base = base % mod;
  while (exp > 0n) {
    if (exp % 2n === 1n) {
      result = (result * base) % mod;
    }
    exp = exp >> 1n;
    base = (base * base) % mod;
  }
  return result;
}

/**
 * RSA OAEP-SHA256 加密（纯 TypeScript 实现）
 */
async function rsaOaepEncrypt(message: Uint8Array, n: bigint, e: bigint): Promise<Uint8Array> {
  const hLen: number = 32; // SHA-256 输出长度
  const k: number = 128; // 1024 位 RSA 模数字节数
  const mLen: number = message.length;

  if (mLen > k - 2 * hLen - 2) {
    throw new Error('RSA OAEP: message too long');
  }

  // 硬编码 SHA256("") 的结果
  const lHash: Uint8Array = new Uint8Array([
    0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14,
    0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
    0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c,
    0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55
  ]);

  let seed: Uint8Array = new Uint8Array(hLen);
  for (let i: number = 0; i < hLen; i++) {
    seed[i] = Math.floor(Math.random() * 256);
  }
  let psLen: number = k - mLen - 2 * hLen - 2;
  let db: Uint8Array = new Uint8Array(k - hLen - 1);
  let off: number = 0;
  db.set(lHash, off);
  off += hLen;
  for (let i = 0; i < psLen; i++) {
    db[off++] = 0x00;
  }
  db[off++] = 0x01;
  db.set(message, off);
  let dbMask: Uint8Array = await mgf1Sha256(seed, k - hLen - 1);
  for (let i = 0; i < db.length; i++) {
    db[i] = db[i] ^ dbMask[i];
  }
  let seedMask: Uint8Array = await mgf1Sha256(db, hLen);
  for (let i = 0; i < hLen; i++) {
    seed[i] = seed[i] ^ seedMask[i];
  }
  let em: Uint8Array = new Uint8Array(k);
  em[0] = 0x00;
  em.set(seed, 1);
  em.set(db, 1 + hLen);
  let m: bigint = 0n;
  for (let i = 0; i < k; i++) {
    m = (m << 8n) + BigInt(em[i]);
  }
  let c: bigint = modPow(m, e, n);
  let ct: Uint8Array = new Uint8Array(k);
  for (let i = k - 1; i >= 0; i--) {
    ct[i] = Number(c & 0xffn);
    c = c >> 8n;
  }
  return ct;
}

/**
 * 生成 correspondPath（RSA OAEP 加密 "refresh_" + 时间戳）
 */
export async function getCorrespondPath(timestamp: number): Promise<string> {
  try {
    let plainText: string = 'refresh_' + timestamp;
    let plainBytes: Uint8Array = new Uint8Array(
      buffer.from(plainText, 'utf-8').buffer as ArrayBuffer
    );
    let derBytes: Uint8Array = new Uint8Array(
      buffer.from(RSA_PUBLIC_KEY_B64, 'base64').buffer as ArrayBuffer
    );
    let key: RsaPubKey = parseRsaPubKeyDer(derBytes);
    let encrypted: Uint8Array = await rsaOaepEncrypt(plainBytes, key.n, key.e);
    return base16Encode(encrypted);
  } catch (e) {
    console.error('[CommonApi] getCorrespondPath 失败:', JSON.stringify(e));
    return '';
  }
}

// ===== SHA-256 =====

const SHA256_K: number[] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

function rotr32(x: number, n: number): number {
  return ((x >>> n) | (x << (32 - n))) >>> 0;
}

/** SHA-256，输入 Uint8Array 输出 32 字节 */
export function sha256(message: Uint8Array): Uint8Array {
  let msgLen: number = message.length;
  let bitLenHi: number = Math.floor(msgLen / 0x20000000) >>> 0;
  let bitLenLo: number = (msgLen * 8) >>> 0;
  let paddedLen: number = (((msgLen + 9 + 63) / 64) | 0) * 64;
  let padded: Uint8Array = new Uint8Array(paddedLen);
  padded.set(message);
  padded[msgLen] = 0x80;
  padded[paddedLen - 8] = (bitLenHi >>> 24) & 0xFF;
  padded[paddedLen - 7] = (bitLenHi >>> 16) & 0xFF;
  padded[paddedLen - 6] = (bitLenHi >>> 8) & 0xFF;
  padded[paddedLen - 5] = bitLenHi & 0xFF;
  padded[paddedLen - 4] = (bitLenLo >>> 24) & 0xFF;
  padded[paddedLen - 3] = (bitLenLo >>> 16) & 0xFF;
  padded[paddedLen - 2] = (bitLenLo >>> 8) & 0xFF;
  padded[paddedLen - 1] = bitLenLo & 0xFF;
  let H: number[] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  for (let blockStart: number = 0; blockStart < paddedLen; blockStart += 64) {
    let W: number[] = new Array<number>(64);
    for (let t: number = 0; t < 16; t++) {
      let idx: number = blockStart + t * 4;
      W[t] = ((padded[idx] << 24) | (padded[idx + 1] << 16) | (padded[idx + 2] << 8) | padded[idx + 3]) >>> 0;
    }
    for (let t: number = 16; t < 64; t++) {
      let s0: number = (rotr32(W[t - 15], 7) ^ rotr32(W[t - 15], 18) ^ (W[t - 15] >>> 3)) >>> 0;
      let s1: number = (rotr32(W[t - 2], 17) ^ rotr32(W[t - 2], 19) ^ (W[t - 2] >>> 10)) >>> 0;
      W[t] = (W[t - 16] + s0 + W[t - 7] + s1) >>> 0;
    }
    let a: number = H[0], b: number = H[1], c: number = H[2], d: number = H[3];
    let e: number = H[4], f: number = H[5], g: number = H[6], h: number = H[7];
    for (let t: number = 0; t < 64; t++) {
      let S1: number = (rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25)) >>> 0;
      let ch: number = ((e & f) ^ ((~e) & g)) >>> 0;
      let temp1: number = (h + S1 + ch + SHA256_K[t] + W[t]) >>> 0;
      let S0: number = (rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22)) >>> 0;
      let maj: number = ((a & b) ^ (a & c) ^ (b & c)) >>> 0;
      let temp2: number = (S0 + maj) >>> 0;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) >>> 0;
    }
    H[0] = (H[0] + a) >>> 0;
    H[1] = (H[1] + b) >>> 0;
    H[2] = (H[2] + c) >>> 0;
    H[3] = (H[3] + d) >>> 0;
    H[4] = (H[4] + e) >>> 0;
    H[5] = (H[5] + f) >>> 0;
    H[6] = (H[6] + g) >>> 0;
    H[7] = (H[7] + h) >>> 0;
  }
  let result: Uint8Array = new Uint8Array(32);
  for (let i: number = 0; i < 8; i++) {
    result[i * 4] = (H[i] >>> 24) & 0xFF;
    result[i * 4 + 1] = (H[i] >>> 16) & 0xFF;
    result[i * 4 + 2] = (H[i] >>> 8) & 0xFF;
    result[i * 4 + 3] = H[i] & 0xFF;
  }
  return result;
}

/**
 * HMAC-SHA256
 * Keys："XgwSnGZ1p"，Message："ts" + 时间戳
 */
export function hmacSha256(key: string, message: string): string {
  let keyBytes: Uint8Array = new Uint8Array(buffer.from(key, 'utf-8').buffer as ArrayBuffer);
  let msgBytes: Uint8Array = new Uint8Array(buffer.from(message, 'utf-8').buffer as ArrayBuffer);
  if (keyBytes.length > 64) {
    keyBytes = sha256(keyBytes);
  }
  let paddedKey: Uint8Array = new Uint8Array(64);
  paddedKey.set(keyBytes);
  let ipad: Uint8Array = new Uint8Array(64);
  let opad: Uint8Array = new Uint8Array(64);
  for (let i: number = 0; i < 64; i++) {
    ipad[i] = paddedKey[i] ^ 0x36;
    opad[i] = paddedKey[i] ^ 0x5C;
  }
  let innerInput: Uint8Array = new Uint8Array(64 + msgBytes.length);
  innerInput.set(ipad);
  innerInput.set(msgBytes, 64);
  let innerHash: Uint8Array = sha256(innerInput);
  let outerInput: Uint8Array = new Uint8Array(64 + 32);
  outerInput.set(opad);
  outerInput.set(innerHash, 64);
  let outerHash: Uint8Array = sha256(outerInput);
  let hex: string = '';
  for (let i: number = 0; i < 32; i++) {
    let h: string = outerHash[i].toString(16);
    if (h.length === 1) {
      hex += '0';
    }
    hex += h;
  }
  return hex;
}

// ===== MurmurHash3 x64 128-bit（完整实现） =====

/** 2^64 */
const MM: bigint = 1n << 64n;
const C1: bigint = 0x87C37B91114253D5n;
const C2: bigint = 0x4CF5AD432745937Fn;
const C3: bigint = 0x52DCE729n;
const C4: bigint = 0x38495AB5n;
const R1: number = 27;
const R2: number = 31;
const R3: number = 33;
const M: number = 5;
const FMIX_C1: bigint = 0xFF51AFD7ED558CCDn;
const FMIX_C2: bigint = 0xC4CEB9FE1A85EC53n;

/** 安全的模运算 */
function mod2p64(x: bigint): bigint {
  return x % MM;
}

/** 64 位循环左移 */
function rotl64(x: bigint, k: number): bigint {
  let kBig: bigint = BigInt(k);
  return mod2p64((x << kBig) | (x >> (64n - kBig)));
}

/** 64 位 fmix（finalizer） */
function fmix64(k: bigint): bigint {
  let x: bigint = k;
  x = mod2p64(x ^ (x >> 33n));
  x = mod2p64(x * FMIX_C1);
  x = mod2p64(x ^ (x >> 33n));
  x = mod2p64(x * FMIX_C2);
  x = mod2p64(x ^ (x >> 33n));
  return x;
}

/** 从 Uint8Array 读取 8 字节为无符号 64 位 BigInt（大端） */
function readUint64LE(buf: Uint8Array, offset: number, len: number): bigint {
  let result: bigint = 0n;
  for (let i: number = len - 1; i >= 0; i--) {
    result = (result << 8n) + BigInt(buf[offset + i]);
  }
  return result;
}

/**
 * MurmurHash3 x64 128-bit 完整实现
 * 输入字节数组，返回 128 位哈希值（BigInt，低 64 位为 h1，高 64 位为 h2）
 */
function murmur3_x64_128(data: Uint8Array, seed: bigint): bigint {
  let h1: bigint = seed;
  let h2: bigint = seed;
  let len: number = data.length;
  let processed: bigint = BigInt(len);
  let pos: number = 0;

  // 处理完整的 16 字节块
  while (pos + 16 <= len) {
    let k1: bigint = readUint64LE(data, pos, 8);
    let k2: bigint = readUint64LE(data, pos + 8, 8);

    h1 = mod2p64(h1 ^ mod2p64(rotl64(mod2p64(k1 * C1), R2) * C2));
    h1 = mod2p64(mod2p64(rotl64(h1, R1) + h2) * BigInt(M) + C3);

    h2 = mod2p64(h2 ^ mod2p64(rotl64(mod2p64(k2 * C2), R3) * C1));
    h2 = mod2p64(mod2p64(rotl64(h2, R2) + h1) * BigInt(M) + C4);

    pos += 16;
  }

  // 处理尾部（剩余 <16 字节）
  if (pos < len) {
    let tailLen: number = len - pos;
    let k1: bigint = 0n;
    let k2: bigint = 0n;

    if (tailLen >= 15) {
      k2 ^= BigInt(data[pos + 14]) << 48n;
    }
    if (tailLen >= 14) {
      k2 ^= BigInt(data[pos + 13]) << 40n;
    }
    if (tailLen >= 13) {
      k2 ^= BigInt(data[pos + 12]) << 32n;
    }
    if (tailLen >= 12) {
      k2 ^= BigInt(data[pos + 11]) << 24n;
    }
    if (tailLen >= 11) {
      k2 ^= BigInt(data[pos + 10]) << 16n;
    }
    if (tailLen >= 10) {
      k2 ^= BigInt(data[pos + 9]) << 8n;
    }
    if (tailLen >= 9) {
      k2 ^= BigInt(data[pos + 8]);
      h2 = mod2p64(h2 ^ mod2p64(rotl64(mod2p64(k2 * C2), R3) * C1));
    }

    if (tailLen >= 8) {
      k1 ^= BigInt(data[pos + 7]) << 56n;
    }
    if (tailLen >= 7) {
      k1 ^= BigInt(data[pos + 6]) << 48n;
    }
    if (tailLen >= 6) {
      k1 ^= BigInt(data[pos + 5]) << 40n;
    }
    if (tailLen >= 5) {
      k1 ^= BigInt(data[pos + 4]) << 32n;
    }
    if (tailLen >= 4) {
      k1 ^= BigInt(data[pos + 3]) << 24n;
    }
    if (tailLen >= 3) {
      k1 ^= BigInt(data[pos + 2]) << 16n;
    }
    if (tailLen >= 2) {
      k1 ^= BigInt(data[pos + 1]) << 8n;
    }
    if (tailLen >= 1) {
      k1 ^= BigInt(data[pos]);
      h1 = mod2p64(h1 ^ mod2p64(rotl64(mod2p64(k1 * C1), R2) * C2));
    }
  }

  // 最终化：融合长度
  h1 = mod2p64(h1 ^ processed);
  h2 = mod2p64(h2 ^ processed);
  h1 = mod2p64(h1 + h2);
  h2 = mod2p64(h2 + h1);
  h1 = fmix64(h1);
  h2 = fmix64(h2);
  h1 = mod2p64(h1 + h2);
  h2 = mod2p64(h2 + h1);

  return (h2 << 64n) | h1;
}

/**
 * 生成 buvid_fp（MurmurHash3 x64 128 位哈希）
 * @param key 输入字符串（通常为 User-Agent + 时间戳）
 * @param seed 种子值（通常为 31）
 * @returns 32 位十六进制字符串
 */
export function genBuvidFp(key: string, seed: bigint): string {
  let u8: Uint8Array = new Uint8Array(buffer.from(key, 'ascii').buffer as ArrayBuffer);
  let result: bigint = murmur3_x64_128(u8, seed);
  let h1: bigint = result & (MM - 1n);
  let h2: bigint = result >> 64n;
  return h1.toString(16).padStart(16, '0') + h2.toString(16).padStart(16, '0');
}
