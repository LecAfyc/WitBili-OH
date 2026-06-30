/**
 * Bilibili WBI 签名算法 —— 与 Python 版逻辑一致（ArkTS 合规）
 */

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';

// mixin key 混淆表（与 Python 完全相同）
const MIXIN_KEY_ENC_TAB: number[] = [
  46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
  27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
  37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
  22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52
];

// 备用 raw key（当网络获取失败时使用）
const FALLBACK_RAW_KEY: string = 'c1a72d2c5d4e8b7f6a3b9e0d8f7c6a5b';

/**
 * MD5 消息摘要（返回 32 位小写十六进制字符串）
 */
async function md5Hex(input: string): Promise<string> {
  let md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
  let uint8Arr: Uint8Array = new Uint8Array(buffer.from(input, 'utf-8').buffer);
  await md.update({ data: uint8Arr } as cryptoFramework.DataBlob);
  let mdResult: cryptoFramework.DataBlob = await md.digest();

  let hex: string = '';
  for (let i: number = 0; i < mdResult.data.length; i++) {
    let h: string = mdResult.data[i].toString(16);
    if (h.length === 1) {
      hex += '0';
    }
    hex += h;
  }
  return hex;
}

/**
 * 生成 mixin key：对 raw key 按混淆表取前 32 个字符
 */
function getMixinKey(rawKey: string): string {
  let key: string = '';
  for (let i: number = 0; i < 32; i++) {
    key += rawKey[MIXIN_KEY_ENC_TAB[i]];
  }
  return key;
}

/**
 * 从 URL 中提取文件名（去掉路径部分）
 */
function getFileNameFromLink(link: string): string {
  let lastSlash: number = link.lastIndexOf('/');
  if (lastSlash >= 0) {
    return link.substring(lastSlash + 1);
  }
  return 'fallback';
}

/**
 * 去掉文件扩展名，只保留文件名主体（若无扩展名则返回整个文件名）
 * 与 Python 的 split('.')[0] 行为一致
 */
function getFileFirstName(file: string): string {
  let dotIndex: number = file.indexOf('.');
  if (dotIndex >= 0) {
    return file.substring(0, dotIndex);
  }
  // 无扩展名时返回原文件名，与 Python 一致
  return file;
}

/**
 * 获取最新的 img_key 和 sub_key（拼接后返回 raw key）
 */
async function fetchWBIRawKey(): Promise<string> {
  console.info("WBIFetch - start")
  let httpRequest: http.HttpRequest = http.createHttp();
  return new Promise<string>((resolve: (value: string) => void) => {
    httpRequest.request(
      'https://api.bilibili.com/x/web-interface/nav',
      {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.95 Safari/537.36',
          'Referer': 'https://www.bilibili.com/',
          'Origin': 'https://www.bilibili.com'
        } as Record<string, string>,
        connectTimeout: 8000,
        readTimeout: 12000
      },
      (err: Error, data: http.HttpResponse) => {
        httpRequest.destroy();
        console.info("WBI - HTTPS End")
        if (err) {
          console.warn('[WbiSign] nav 请求失败，使用备用 key');
          resolve(FALLBACK_RAW_KEY);
          return;
        }
        try {
          console.info("[wbiSign] Result - " + JSON.stringify(data.result))
          let result: Record<string, Object> = JSON.parse(data.result as string) as Record<string, Object>;
          let navData: Record<string, Object> = result['data'] as Record<string, Object>;
          if (!navData) {
            resolve(FALLBACK_RAW_KEY);
            return;
          }
          let wbiImg: Record<string, string> = navData['wbi_img'] as Record<string, string>;
          if (!wbiImg) {
            resolve(FALLBACK_RAW_KEY);
            return;
          }
          let imgUrl: string = wbiImg['img_url'] || '';
          let subUrl: string = wbiImg['sub_url'] || '';
          let imgKey: string = getFileFirstName(getFileNameFromLink(imgUrl));
          let subKey: string = getFileFirstName(getFileNameFromLink(subUrl));
          console.info("WBI - imgKey= " + imgKey + " subKey= " + subKey)
          resolve(imgKey + subKey);
        } catch (e) {
          console.warn('[WbiSign] nav 解析失败，使用备用 key');
          resolve(FALLBACK_RAW_KEY);
        }
      }
    );
  });
}

/**
 * 将参数字典按 key 排序、过滤特殊字符、编码后生成 query 字符串
 * 与 Python 的 urlencode(params) 等价（空格编码为 '+'）
 */
function buildQueryString(params: Record<string, string>): string {
  let sortedKeys: string[] = Object.keys(params).sort();
  let pairs: string[] = [];
  for (let key of sortedKeys) {
    let rawValue: string = params[key];
    // 过滤掉字符 !'()* （与 Python 一致）
    let filteredValue: string = '';
    for (let ch of rawValue) {
      if ("!'()*".indexOf(ch) === -1) {
        filteredValue += ch;
      }
    }
    // URL 编码，并将 %20 替换为 +，模拟 Python 的 quote_plus
    let encodedKey: string = encodeURIComponent(key).replace(/%20/g, '+');
    let encodedValue: string = encodeURIComponent(filteredValue).replace(/%20/g, '+');
    pairs.push(encodedKey + '=' + encodedValue);
  }
  return pairs.join('&');
}

/**
 * 对参数对象进行 WBI 签名，返回签名后的参数对象（包含 w_rid 和 wts）
 * @param params 原始参数（值可以是 string 或 number）
 * @returns 签名后的参数字典
 */
async function encWbiParams(params: Record<string, string | number>): Promise<Record<string, string>> {
  let rawKey: string;
  try {
    rawKey = await fetchWBIRawKey();
  } catch (e) {
    console.warn('[WbiSign] 获取 key 失败，使用备用 key');
    rawKey = FALLBACK_RAW_KEY;
  }

  let mixinKey: string = getMixinKey(rawKey);
  let wts: number = Math.floor(Date.now() / 1000);

  // 将所有参数值转为字符串（使用 Object.keys 替代 for..in）
  let stringParams: Record<string, string> = {};
  for (let k of Object.keys(params)) {
    stringParams[k] = String(params[k]);
  }
  // 添加 wts
  stringParams['wts'] = String(wts);

  // 构建 query 字符串（已排序、过滤、编码）
  let query: string = buildQueryString(stringParams);

  // 计算签名
  let wbiSign: string = await md5Hex(query + mixinKey);

  // 返回完整参数（保留原始过滤和编码后的值，方便拼接 URL）
  // 这里直接返回一个包含 w_rid 的新字典，value 为过滤后的字符串形式
  let result: Record<string, string> = {};
  // 重新从已处理的 query 解析参数，保证一致
  let queryPairs: string[] = query.split('&');
  for (let pair of queryPairs) {
    let eqIndex: number = pair.indexOf('=');
    if (eqIndex > 0) {
      let k: string = decodeURIComponent(pair.substring(0, eqIndex).replace(/\+/g, ' '));
      let v: string = pair.substring(eqIndex + 1);
      // 解码回原始过滤后的值，方便直接使用（调用方自己再编码）
      result[k] = decodeURIComponent(v.replace(/\+/g, ' '));
    }
  }
  result['w_rid'] = wbiSign;
  return result;
}

/**
 * 对 URL 进行 WBI 签名（兼容原有接口）
 * @param url 原始 URL（可带 ? 参数）
 * @returns 签名后的完整 URL
 */
export async function signWBI(url: string): Promise<string> {
  // 分离 base 和 query
  let qmIndex: number = url.indexOf('?');
  let base: string = qmIndex >= 0 ? url.substring(0, qmIndex) : url;
  let queryStr: string = qmIndex >= 0 ? url.substring(qmIndex + 1) : '';

  // 解析原始参数
  let params: Record<string, string | number> = {};
  if (queryStr) {
    let pairs: string[] = queryStr.split('&');
    for (let pair of pairs) {
      let eq: number = pair.indexOf('=');
      if (eq > 0) {
        let key: string = decodeURIComponent(pair.substring(0, eq).replace(/\+/g, ' '));
        let value: string = decodeURIComponent(pair.substring(eq + 1).replace(/\+/g, ' '));
        params[key] = value;
      } else if (eq === -1 && pair.length > 0) {
        params[pair] = '';
      }
    }
  }

  // 调用核心签名
  let signedParams: Record<string, string> = await encWbiParams(params);

  // 对整个参数字典重新编码（w_rid 也会被包含，与 Python 行为一致）
  let finalQuery: string = buildQueryString(signedParams);

  return base + '?' + finalQuery;
}