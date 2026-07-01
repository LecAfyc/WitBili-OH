/**
 * Bilibili 弹幕 API
 *
 */

import { BarrageItem } from '@esky/barrage';
import { decodeHTML, httpGetText } from './CommonApi';

// ===== 类型定义 =====

/** 解析后的单条弹幕原始数据（轻量，只含 string/number） */
export interface DanmakuData {
  /** 视频内出现时间（秒） */
  time: number;

  /** 弹幕类型：1-3=滚动，4=底部，5=顶部，6=逆向 */
  type: number;

  /** 字号：18=小，25=标准，36=大 */
  fontSize: number;

  /** 颜色（十进制 RGB888） */
  color: number;

  /** 发送时间戳 */
  sendTimestamp: number;

  /** 弹幕池：0=普通，1=字幕，2=特殊 */
  pool: number;

  /** 发送者 mid 的 hash */
  senderHash: string;

  /** 弹幕 dmid */
  dmid: number;

  /** 弹幕文本 */
  text: string;
}

// ===== 颜色转换 =====

/** 十进制 RGB888 -> #AARRGGBB 格式 Hex 字符串 */
function decColorToHex(colorDec: number): string {
  let r: number = (colorDec >> 16) & 0xFF;
  let g: number = (colorDec >> 8) & 0xFF;
  let b: number = colorDec & 0xFF;
  return '#ff'
    + r.toString(16).padStart(2, '0')
    + g.toString(16).padStart(2, '0')
    + b.toString(16).padStart(2, '0');
}

// ===== 字号映射 =====

/** 将 B 站字号（18/25/36）映射为 BarrageItem textSize（vp，比默认偏小） */
function mapFontSize(size: number): number {
  if (size <= 18) {
    return 9;
  }
  if (size >= 36) {
    return 13;
  }
  return 11;
}

// ===== 弹幕速度 =====

/** 根据文本长度计算弹幕滚动速度（调快） */
function calcSpeed(text: string): number {
  let len: number = text.length;
  if (len <= 5) {
    return 2.2;
  }
  if (len <= 10) {
    return 2.8;
  }
  if (len <= 20) {
    return 3.2;
  }
  return 3.6;
}

// ===== 弹幕类型过滤 =====

/** 判断是否是需要显示的弹幕类型（仅保留普通弹幕 1-6） */
function isAllowedType(type: number, _pool: number): boolean {
  // type 1-6 均为普通弹幕（滚动/底部/顶部/逆向）
  if (type >= 1 && type <= 6) {
    return true;
  }
  // 排除高级弹幕(7)、代码弹幕(8)、BAS 弹幕(9 + pool=2)
  return false;
}

// ===== XML 解析 =====

/**
 * 解析 Bilibili 弹幕 XML 文本
 *
 * @param xmlText 经过 deflate 解压后的 XML 字符串
 * @returns 解析后的弹幕数据列表（仅含 string/number，不创建 BarrageItem）
 */
export function parseDanmakuXml(xmlText: string): Array<DanmakuData> {
  let result: Array<DanmakuData> = [];
  let pos: number = 0;

  while (true) {
    // 查找 <d 标签起始
    let dStart: number = xmlText.indexOf('<d', pos);
    if (dStart === -1) {
      break;
    }

    // 提取 p 属性值
    let pStart: number = xmlText.indexOf('p="', dStart);
    if (pStart === -1) {
      break;
    }
    pStart += 3; // 跳过 p="

    let pEnd: number = xmlText.indexOf('"', pStart);
    if (pEnd === -1) {
      break;
    }
    let pVal: string = xmlText.substring(pStart, pEnd);

    // 找到标签结束 >
    let tagEnd: number = xmlText.indexOf('>', pEnd);
    if (tagEnd === -1) {
      break;
    }

    // 找到 </d> 闭合标签
    let closeStart: number = xmlText.indexOf('</d>', tagEnd);
    if (closeStart === -1) {
      break;
    }

    // 提取弹幕文本
    let text: string = xmlText.substring(tagEnd + 1, closeStart);

    // 解析 p 属性（8 个逗号分隔值）
    let parts: Array<string> = pVal.split(',');
    if (parts.length >= 8) {
      result.push({
        time: parseFloat(parts[0]),
        type: parseInt(parts[1]),
        fontSize: parseInt(parts[2]),
        color: parseInt(parts[3]),
        sendTimestamp: parseInt(parts[4]),
        pool: parseInt(parts[5]),
        senderHash: parts[6],
        dmid: parseInt(parts[7]),
        text: decodeHTML(text)
      });
    }

    pos = closeStart + 4;
  }

  return result;
}

// ===== 懒加载：按需创建 BarrageItem =====

/**
 * 将 DanmakuData 转换为 BarrageItem（懒加载，只在需要显示时调用）
 *
 * @param d 轻量弹幕数据
 * @returns 可用于 BarrageView.addBarrage() 的 BarrageItem
 */
export function createBarrageItem(d: DanmakuData): BarrageItem {
  let item: BarrageItem = new BarrageItem();
  item.text = d.text;
  item.textColor = [decColorToHex(d.color)];
  item.textSize = mapFontSize(d.fontSize);
  item.speed = calcSpeed(d.text);
  item.isSelf = false;
  item.timeStamp = d.sendTimestamp.toString();
  // 顶部弹幕（type=5）优先级略高
  if (d.type === 5) {
    item.priority = 1;
  }
  return item;
}

// ===== 获取弹幕（对外接口） =====

/**
 * 获取视频的实时弹幕数据
 *
 * 调用 Bilibili XML 弹幕接口（deflate 压缩由 CommonApi 的 HTTP 栈自动解压），
 * 返回**轻量** DanmakuData[]，不创建 BarrageItem 对象。
 * BarrageItem 由调用方通过 createBarrageItem() 按需创建。
 *
 * @param cid 视频分P cid
 * @returns 过滤后按视频时间升序排列的 DanmakuData[]
 */
export async function getDanmakuItems(cid: number): Promise<Array<DanmakuData>> {
  let url: string = 'https://comment.bilibili.com/' + cid.toString() + '.xml';
  console.info('[DanmakuApi] 请求弹幕: ' + url);

  // 通过 CommonApi 的 httpGetText 请求（自动处理 deflate 解压）
  let xmlText: string = await httpGetText(url, {
    logTag: '[DanmakuApi]'
  });

  // 验证是否是有效的 XML（已解压的标志：以 '<' 或 '<?xml' 开头）
  if (!xmlText.startsWith('<')) {
    console.warn('[DanmakuApi] 响应不是以 < 开头，可能未正确解压（deflate），尝试继续解析...');
  }

  let all: Array<DanmakuData> = parseDanmakuXml(xmlText);
  console.info('[DanmakuApi] 解析弹幕 ' + all.length + ' 条');

  // 过滤类型
  let filtered: Array<DanmakuData> = [];
  for (let i: number = 0; i < all.length; i++) {
    let d: DanmakuData = all[i];
    if (isAllowedType(d.type, d.pool)) {
      filtered.push(d);
    }
  }

  // 按视频时间排序
  filtered.sort((a: DanmakuData, b: DanmakuData) => a.time - b.time);

  console.info('[DanmakuApi] 过滤后弹幕 ' + filtered.length + ' 条');
  return filtered;
}
