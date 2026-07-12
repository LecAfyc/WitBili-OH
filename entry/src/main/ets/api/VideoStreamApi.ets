/**
 * 视频流解析 API
 * 优先使用 durl（MP4 音视频合一），无则降级到 DASH（音视频分离）
 */

import { ApiResponse, httpGet } from './CommonApi';
import { signWBI } from './WbiSign';

// ===== DASH 数据模型 =====

/** DASH 视频流 */
export interface DashVideoStream {
  id: number; // 清晰度代码（16=360P, 32=480P, 64=720P, 80=1080P, …）
  baseUrl: string; // 默认流 URL
  backupUrl: string[]; // 备用流 URL
  bandwidth: number; // 所需最低带宽
  mimeType: string; // 格式 mimeType
  codecs: string; // 编码类型（avc1.640028 / hev1.1.6.L153.B0 / av01.0.05M.08 等）
  width: number; // 视频宽度（像素）
  height: number; // 视频高度（像素）
  frameRate: string; // 视频帧率
  codecid: number; // 码流编码标识代码（7=AVC, 12=HEVC, 13=AV1）
}

/** DASH 音频流 */
export interface DashAudioStream {
  id: number; // 音质代码
  baseUrl: string; // 默认流 URL
  backupUrl: string[]; // 备用流 URL
  bandwidth: number; // 码率
  mimeType: string; // 格式 mimeType
  codecs: string; // 音频编码（mp4a.40.2 / mp4a.40.5 等）
  codecid: number; // 编码标识（音频流恒为 0）
}

/** DASH 顶层数据 */
export interface DashData {
  duration: number; // 视频长度（秒）
  minBufferTime: number; // 最小缓冲时间
  videoStreams: DashVideoStream[]; // 视频流列表（按清晰度从高到低）
  audioStreams: DashAudioStream[]; // 音频流列表（按码率从高到低）
  dolbyAudio: DashAudioStream | null; // 杜比全景声音频
  flacAudio: DashAudioStream | null; // 无损音轨音频
  streamType: number; // 流类型（0=video, 1=audio_only）
}

/** DASH 流返回结果 */
export interface DashPlayUrlResult {
  /** 选中的视频流 URL */
  videoUrl: string;

  /** 选中的音频流 URL（可能是 flac/杜比/最高码率普通音频） */
  audioUrl: string;

  /** 完整 DASH 数据 */
  dashData: DashData;

  /** 可用清晰度描述列表 */
  acceptDescription: string[];

  /** 可用清晰度值列表 */
  acceptQuality: number[];

  /** 续播进度（秒） */
  lastPlayTime: number;

  /** 弹幕 URL */
  danmakuUrl: string;

  /** 是否为 DASH 格式（false 表示 fallback 到了 durl） */
  isDash: boolean;
}


/**
 * 获取最高质量的音频流
 * 优先级：无损音轨 > 杜比全景声 > 最高码率普通音频
 */
function getBestAudioStream(dashData: DashData): DashAudioStream | null {
  // 优先返回无损音轨
  if (dashData.flacAudio !== null) {
    return dashData.flacAudio;
  }
  // 其次返回杜比全景声
  if (dashData.dolbyAudio !== null) {
    return dashData.dolbyAudio;
  }
  // 返回最高码率的普通音频流
  if (dashData.audioStreams.length > 0) {
    let best: DashAudioStream = dashData.audioStreams[0];
    for (let i: number = 1; i < dashData.audioStreams.length; i++) {
      if (dashData.audioStreams[i].bandwidth > best.bandwidth) {
        best = dashData.audioStreams[i];
      }
    }
    return best;
  }
  return null;
}

// ===== JSON 解析 =====

/**
 * 从 JSON 对象解析单个 DASH 视频流
 */
function parseDashVideoStream(json: Record<string, Object>): DashVideoStream {
  let id: number = (json['id'] as number) || 0;
  let baseUrl: string = (json['baseUrl'] as string) || (json['base_url'] as string) || '';
  let bandwidth: number = (json['bandwidth'] as number) || 0;
  let mimeType: string = (json['mimeType'] as string) || (json['mime_type'] as string) || '';
  let codecs: string = (json['codecs'] as string) || '';
  let width: number = (json['width'] as number) || 0;
  let height: number = (json['height'] as number) || 0;
  let frameRate: string = (json['frameRate'] as string) || (json['frame_rate'] as string) || '';
  let codecid: number = (json['codecid'] as number) || 0;

  // 解析备用 URL（兼容 backupUrl / backup_url 两种 key）
  let backupUrl: string[] = [];
  let backupRaw: Object[] | undefined = (json['backupUrl'] as Object[]) || (json['backup_url'] as Object[]);
  if (backupRaw) {
    for (let i: number = 0; i < backupRaw.length; i++) {
      backupUrl.push(backupRaw[i] as string);
    }
  }

  return {
    id: id,
    baseUrl: baseUrl,
    backupUrl: backupUrl,
    bandwidth: bandwidth,
    mimeType: mimeType,
    codecs: codecs,
    width: width,
    height: height,
    frameRate: frameRate,
    codecid: codecid
  };
}

/**
 * 从 JSON 对象解析单个 DASH 音频流
 */
function parseDashAudioStream(json: Record<string, Object>): DashAudioStream {
  let id: number = (json['id'] as number) || 0;
  let baseUrl: string = (json['baseUrl'] as string) || (json['base_url'] as string) || '';
  let bandwidth: number = (json['bandwidth'] as number) || 0;
  let mimeType: string = (json['mimeType'] as string) || (json['mime_type'] as string) || '';
  let codecs: string = (json['codecs'] as string) || '';
  let codecid: number = (json['codecid'] as number) || 0;

  let backupUrl: string[] = [];
  let backupRaw: Object[] | undefined = (json['backupUrl'] as Object[]) || (json['backup_url'] as Object[]);
  if (backupRaw) {
    for (let i: number = 0; i < backupRaw.length; i++) {
      backupUrl.push(backupRaw[i] as string);
    }
  }

  return {
    id: id,
    baseUrl: baseUrl,
    backupUrl: backupUrl,
    bandwidth: bandwidth,
    mimeType: mimeType,
    codecs: codecs,
    codecid: codecid
  };
}

/**
 * 从 API 返回的 JSON 解析整个 DASH 数据
 */
function parseDashData(dashJson: Record<string, Object>): DashData {
  let duration: number = (dashJson['duration'] as number) || 0;
  let minBufferTime: number = (dashJson['minBufferTime'] as number) || (dashJson['min_buffer_time'] as number) || 1.5;
  let streamType: number = (dashJson['stream_type'] as number) || 0;

  // 解析视频流
  let videoStreams: DashVideoStream[] = [];
  let videoRaw: Object[] | undefined = dashJson['video'] as Object[];
  if (videoRaw) {
    for (let i: number = 0; i < videoRaw.length; i++) {
      videoStreams.push(parseDashVideoStream(videoRaw[i] as Record<string, Object>));
    }
  }

  // 解析音频流
  let audioStreams: DashAudioStream[] = [];
  let audioRaw: Object[] | undefined = dashJson['audio'] as Object[];
  if (audioRaw) {
    for (let i: number = 0; i < audioRaw.length; i++) {
      audioStreams.push(parseDashAudioStream(audioRaw[i] as Record<string, Object>));
    }
  }

  // 解析杜比全景声
  let dolbyAudio: DashAudioStream | null = null;
  let dolbyObj: Record<string, Object> | undefined = dashJson['dolby'] as Record<string, Object>;
  if (dolbyObj) {
    let dolbyType: number = (dolbyObj['type'] as number) || 0;
    if (dolbyType > 0) {
      let dolbyAudioRaw: Object | undefined = dolbyObj['audio'];
      if (dolbyAudioRaw) {
        // audio 可能是对象也可能是数组，取第一个
        let dolbyAudioObj: Record<string, Object> | null = null;
        if (dolbyAudioRaw instanceof Array) {
          let arr: Object[] = dolbyAudioRaw;
          if (arr.length > 0) {
            dolbyAudioObj = arr[0] as Record<string, Object>;
          }
        } else {
          dolbyAudioObj = dolbyAudioRaw as Record<string, Object>;
        }
        if (dolbyAudioObj) {
          dolbyAudio = parseDashAudioStream(dolbyAudioObj);
        }
      }
    }
  }

  // 解析无损音轨
  let flacAudio: DashAudioStream | null = null;
  let flacObj: Record<string, Object> | undefined = dashJson['flac'] as Record<string, Object>;
  if (flacObj) {
    let flacDisplay: boolean = (flacObj['display'] as boolean) || false;
    if (flacDisplay) {
      let flacAudioRaw: Object | undefined = flacObj['audio'];
      if (flacAudioRaw) {
        let flacAudioObj: Record<string, Object> = flacAudioRaw as Record<string, Object>;
        flacAudio = parseDashAudioStream(flacAudioObj);
      }
    }
  }

  return {
    duration: duration,
    minBufferTime: minBufferTime,
    videoStreams: videoStreams,
    audioStreams: audioStreams,
    dolbyAudio: dolbyAudio,
    flacAudio: flacAudio,
    streamType: streamType
  };
}


/**
 * 从 DASH 数据中获取指定清晰度的视频流
 * 若找不到指定 qn，返回第一个最高清晰度的流
 */
function getVideoStreamForQn(dashData: DashData, qn: number): DashVideoStream | null {
  for (let i: number = 0; i < dashData.videoStreams.length; i++) {
    if (dashData.videoStreams[i].id === qn) {
      return dashData.videoStreams[i];
    }
  }
  // 找不到时返回第一个（最高清晰度）
  if (dashData.videoStreams.length > 0) {
    return dashData.videoStreams[0];
  }
  return null;
}

// ===== 主 API =====

/**
 * 构建请求 URL 并获取视频流 API 响应数据
 * @param fnval 视频流格式标识（1=MP4/durl, 4048=全部DASH）
 */
async function fetchPlayUrlData(bvid: string, cid: number, qn: number, fnval: number): Promise<Record<string, Object>> {
  let url: string = 'https://api.bilibili.com/x/player/wbi/playurl?'
    + 'bvid=' + encodeURIComponent(bvid)
    + '&cid=' + cid.toString()
    + '&qn=' + qn.toString()
    + '&fnval=' + fnval.toString()
    + '&fnver=0'
    + '&platform=pc'
    + '&voice_balance=1'
    + '&gaia_source=pre-load'
    + '&isGaiaAvoided=true';

  let signedUrl: string = await signWBI(url);
  console.info('[VideoStreamApi] signed playurl (fnval=' + fnval + '): ' + signedUrl);

  let resp: ApiResponse = await httpGet(signedUrl);
  if (resp.code !== 0) {
    throw new Error('获取视频流失败: code=' + resp.code + ' msg=' + resp.message);
  }
  if (!resp.data) {
    throw new Error('获取视频流失败: data 为空');
  }

  return resp.data as Record<string, Object>;
}

/**
 * 获取视频播放地址
 * 优先使用 durl（MP4 音视频合一，fnval=1），无则降级到 DASH（fnval=4048）
 *
 * @param bvid 稿件 bvid
 * @param cid  分P cid
 * @param qn   目标清晰度（如 80=1080P, 64=720P, 32=480P）
 */
export async function getDashPlayUrl(bvid: string, cid: number, qn: number): Promise<DashPlayUrlResult> {
  let danmakuUrl: string = 'https://comment.bilibili.com/' + cid.toString() + '.xml';

  // 第一轮：优先请求 MP4/durl 格式（fnval=1）
  console.info('[VideoStreamApi] 优先请求 MP4/durl 格式');
  let durlData: Record<string, Object>;
  try {
    durlData = await fetchPlayUrlData(bvid, cid, qn, 1);
  } catch (e) {
    console.info('[VideoStreamApi] MP4 请求异常，尝试 DASH 降级: ' + String(e));
    return await fetchAndParseDash(bvid, cid, qn, danmakuUrl);
  }

  let acceptDescription: string[] = (durlData['accept_description'] as string[]) || [];
  let acceptQuality: number[] = (durlData['accept_quality'] as number[]) || [];
  let lastPlayTime: number = (durlData['last_play_time'] as number) || 0;

  let durl: Object[] = (durlData['durl'] as Object[]) || [];
  if (durl.length > 0) {
    console.info('[VideoStreamApi] durl 数据存在，使用 MP4 流');
    let firstSeg: Record<string, Object> = durl[0] as Record<string, Object>;
    let rawUrl: string = (firstSeg['url'] as string) || '';
    let videoUrl: string = rawUrl.replace(/\\u0026/g, '&');

    let emptyDashData: DashData = {
      duration: 0,
      minBufferTime: 1.5,
      videoStreams: [],
      audioStreams: [],
      dolbyAudio: null,
      flacAudio: null,
      streamType: 0
    };

    return {
      videoUrl: videoUrl,
      audioUrl: '',
      dashData: emptyDashData,
      acceptDescription: acceptDescription,
      acceptQuality: acceptQuality,
      lastPlayTime: lastPlayTime,
      danmakuUrl: danmakuUrl,
      isDash: false
    };
  }

  // 第二轮：降级到 DASH（fnval=4048，全部 DASH 流）
  console.info('[VideoStreamApi] 无 durl 数据，降级到 DASH');
  return await fetchAndParseDash(bvid, cid, qn, danmakuUrl);
}

/**
 * 请求 DASH 格式并解析
 */
async function fetchAndParseDash(bvid: string, cid: number, qn: number, danmakuUrl: string): Promise<DashPlayUrlResult> {
  let dashDataRaw: Record<string, Object> = await fetchPlayUrlData(bvid, cid, qn, 4048);

  let acceptDescription: string[] = (dashDataRaw['accept_description'] as string[]) || [];
  let acceptQuality: number[] = (dashDataRaw['accept_quality'] as number[]) || [];
  let lastPlayTime: number = (dashDataRaw['last_play_time'] as number) || 0;

  let dashRaw: Record<string, Object> | undefined = dashDataRaw['dash'] as Record<string, Object>;
  if (dashRaw) {
    console.info('[VideoStreamApi] DASH 数据存在，解析 DASH 流');

    let dashData: DashData = parseDashData(dashRaw);

    let videoStream: DashVideoStream | null = getVideoStreamForQn(dashData, qn);
    let videoUrl: string = '';
    if (videoStream) {
      videoUrl = videoStream.baseUrl;
      console.info('[VideoStreamApi] 选中视频流: id=' + videoStream.id
        + ', codecs=' + videoStream.codecs
        + ', ' + videoStream.width + 'x' + videoStream.height);
    }

    let audioStream: DashAudioStream | null = getBestAudioStream(dashData);
    let audioUrl: string = '';
    if (audioStream) {
      audioUrl = audioStream.baseUrl;
      console.info('[VideoStreamApi] 选中音频流: id=' + audioStream.id
        + ', codecs=' + audioStream.codecs
        + ', bandwidth=' + audioStream.bandwidth);
    }

    return {
      videoUrl: videoUrl,
      audioUrl: audioUrl,
      dashData: dashData,
      acceptDescription: acceptDescription,
      acceptQuality: acceptQuality,
      lastPlayTime: lastPlayTime,
      danmakuUrl: danmakuUrl,
      isDash: true
    };
  }

  throw new Error('获取视频地址失败: 既无 durl 也无 DASH');
}
