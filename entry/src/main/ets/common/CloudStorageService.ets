import { cloudStorage } from '@kit.CloudFoundationKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError, request } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'CloudStorageService';

/** 图片压缩最长边（像素），超过则等比缩放 */
const IMAGE_MAX_SIDE = 1920;
/** 图片压缩 JPEG 质量（1-100） */
const IMAGE_JPEG_QUALITY = 75;
/** 头像裁剪输出边长（像素），中心正方形裁剪后缩放到此尺寸 */
const AVATAR_SIZE = 512;

/**
 * Cloud Storage 服务
 * 封装 AGC 云存储的文件上传、下载、删除、获取 URL 等操作
 * 默认存储桶: aoyou-3wuha（agconnect-services.json 中 default_storage 配置）
 *
 * 云存储路径约定（参照 doc/云数据库数据模型详细设计v1.0.md）：
 *  - 轨迹封面:  tracks/{trackId}/cover.jpg
 *  - 打卡点图片: tracks/{trackId}/tombs/{tombId}/{index}.jpg
 *  - 用户头像:  users/{userId}/avatar.jpg
 */
export class CloudStorageService {

  // ==================== 工具方法 ====================

  /**
   * 判断路径是否为本地路径（非云端 URL）
   * 本地路径：以 / 开头的绝对路径、file:// URI、datashare:// URI
   * 云端 URL：以 http:// 或 https:// 开头
   */
  static isLocalPath(path: string): boolean {
    if (path.length === 0) {
      return false;
    }
    // 云端 URL 或无效标记路径，均不视为本地路径
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('cloud://')) {
      return false;
    }
    return true;
  }

  /**
   * 从路径中提取文件扩展名，默认返回 'jpg'
   */
  static getFileExtension(path: string): string {
    const lastDot = path.lastIndexOf('.');
    if (lastDot >= 0 && lastDot < path.length - 1) {
      let ext = path.substring(lastDot + 1).toLowerCase();
      // 去除可能的查询参数
      const queryIdx = ext.indexOf('?');
      if (queryIdx > 0) {
        ext = ext.substring(0, queryIdx);
      }
      // 只保留合法的图片扩展名
      if (ext === 'jpg' || ext === 'jpeg' || ext === 'png' || ext === 'webp' || ext === 'gif') {
        return ext;
      }
    }
    return 'jpg';
  }

  // ==================== 图片压缩 ====================

  /**
   * 压缩图片并保存到缓存目录，返回缓存文件路径
   * - 支持 file:// URI、datashare:// URI、绝对路径
   * - 自动等比缩放至最长边不超过 IMAGE_MAX_SIDE（1920px）
   * - 输出 JPEG 格式，质量 IMAGE_JPEG_QUALITY（75%）
   * - 用于上传前的预处理，显著减小文件体积
   */
  static async compressImageToCache(context: common.Context, srcPath: string, fileName: string): Promise<string> {
    try {
      const cacheDir: string = context.cacheDir;
      const destPath: string = cacheDir + '/' + fileName;

      hilog.info(LOG_DOMAIN, LOG_TAG, 'Compressing: %{public}s', srcPath);

      // 1. 打开文件获取 fd（支持 file://media/... URI 和绝对路径）
      const srcFile: fileIo.File = fileIo.openSync(srcPath, fileIo.OpenMode.READ_ONLY);

      // 2. 通过 fd 创建 ImageSource（createImageSource 不直接支持 file:// URI）
      const imgSource: image.ImageSource = image.createImageSource(srcFile.fd);

      // 2. 获取原始图片信息（宽高）
      const imgInfo: image.ImageInfo = await imgSource.getImageInfo();
      const origWidth: number = imgInfo.size.width;
      const origHeight: number = imgInfo.size.height;

      hilog.info(LOG_DOMAIN, LOG_TAG, 'Image original: %{public}dx%{public}d', origWidth, origHeight);

      // 3. 计算缩放后的目标尺寸（最长边不超过 IMAGE_MAX_SIDE）
      let targetWidth: number = origWidth;
      let targetHeight: number = origHeight;
      const maxSide: number = Math.max(origWidth, origHeight);
      if (maxSide > IMAGE_MAX_SIDE) {
        const scale: number = IMAGE_MAX_SIDE / maxSide;
        targetWidth = Math.round(origWidth * scale);
        targetHeight = Math.round(origHeight * scale);
      }

      // 4. 解码为 PixelMap（指定目标尺寸实现缩放）
      const decodingOpts: image.DecodingOptions = {
        desiredSize: { width: targetWidth, height: targetHeight }
      };
      const pixelMap: image.PixelMap = await imgSource.createPixelMap(decodingOpts);

      hilog.info(LOG_DOMAIN, LOG_TAG, 'Image resized: %{public}dx%{public}d', targetWidth, targetHeight);

      // 5. 压缩为 JPEG
      const packer: image.ImagePacker = image.createImagePacker();
      const packOpts: image.PackingOption = {
        format: 'image/jpeg',
        quality: IMAGE_JPEG_QUALITY
      };
      const compressedData: ArrayBuffer = await packer.packToData(pixelMap, packOpts);

      // 6. 写入缓存文件
      const dstFile: fileIo.File = fileIo.openSync(destPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(dstFile.fd, compressedData);
      fileIo.closeSync(dstFile);

      // 7. 释放资源
      packer.release();
      pixelMap.release();
      imgSource.release();
      fileIo.closeSync(srcFile);

      const sizeKB: number = Math.round(compressedData.byteLength / 1024);
      hilog.info(LOG_DOMAIN, LOG_TAG, '✅ Image compressed: %{public}s (%{public}dKB)', destPath, sizeKB);
      return destPath;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, '❌ Compress image failed [%{public}s]: code=%{public}d, msg=%{public}s',
        srcPath, err.code || 0, err.message || '');
      return '';
    }
  }

  /**
   * 头像专用：中心正方形裁剪 + 缩放到 AVATAR_SIZE，再压缩为 JPEG 写入缓存
   * - 先解码（最长边不超过 1024 以省内存），再裁成中心正方形，再缩放到 512x512，最后打包
   * @returns 缓存文件路径；失败返回空字符串
   */
  static async compressAndCropAvatarToCache(context: common.Context, srcPath: string, fileName: string): Promise<string> {
    try {
      const cacheDir: string = context.cacheDir;
      const destPath: string = cacheDir + '/' + fileName;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Avatar crop: %{public}s', srcPath);

      const srcFile: fileIo.File = fileIo.openSync(srcPath, fileIo.OpenMode.READ_ONLY);
      const imgSource: image.ImageSource = image.createImageSource(srcFile.fd);
      const imgInfo: image.ImageInfo = await imgSource.getImageInfo();
      const origWidth: number = imgInfo.size.width;
      const origHeight: number = imgInfo.size.height;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Avatar original: %{public}dx%{public}d', origWidth, origHeight);

      // 解码时限制最长边 1024，减少大图内存
      let decodeW: number = origWidth;
      let decodeH: number = origHeight;
      const maxDecode: number = 1024;
      if (Math.max(origWidth, origHeight) > maxDecode) {
        const scale: number = maxDecode / Math.max(origWidth, origHeight);
        decodeW = Math.round(origWidth * scale);
        decodeH = Math.round(origHeight * scale);
      }
      const decodingOpts: image.DecodingOptions = {
        desiredSize: { width: decodeW, height: decodeH }
      };
      const pixelMap: image.PixelMap = await imgSource.createPixelMap(decodingOpts);
      imgSource.release();
      fileIo.closeSync(srcFile);

      // 中心正方形裁剪（在解码后的尺寸上）
      const w: number = decodeW;
      const h: number = decodeH;
      const side: number = Math.min(w, h);
      const x: number = Math.floor((w - side) / 2);
      const y: number = Math.floor((h - side) / 2);
      const region: image.Region = {
        x: x,
        y: y,
        size: { width: side, height: side }
      };
      await pixelMap.crop(region);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Avatar cropped to square: %{public}d', side);

      // 若大于目标边长则缩放
      if (side > AVATAR_SIZE) {
        const scaleFactor: number = AVATAR_SIZE / side;
        await pixelMap.scale(scaleFactor, scaleFactor);
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Avatar scaled to: %{public}d', AVATAR_SIZE);
      }

      const packer: image.ImagePacker = image.createImagePacker();
      const packOpts: image.PackingOption = { format: 'image/jpeg', quality: IMAGE_JPEG_QUALITY };
      const compressedData: ArrayBuffer = await packer.packToData(pixelMap, packOpts);
      packer.release();
      pixelMap.release();

      const dstFile: fileIo.File = fileIo.openSync(destPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(dstFile.fd, compressedData);
      fileIo.closeSync(dstFile);

      const sizeKB: number = Math.round(compressedData.byteLength / 1024);
      hilog.info(LOG_DOMAIN, LOG_TAG, '✅ Avatar cropped & saved: %{public}s (%{public}dKB)', destPath, sizeKB);
      return destPath;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, '❌ Avatar crop failed [%{public}s]: code=%{public}d, msg=%{public}s',
        srcPath, err.code || 0, err.message || '');
      return '';
    }
  }

  // ==================== 核心上传 ====================

  /**
   * 上传本地文件到云存储，返回下载 URL
   *
   * ★ 关键说明（对齐华为官方示例 StoragePage.ets）：
   *   1. localPath 必须是 **相对于 cacheDir 的文件名**，而非绝对路径
   *   2. uploadFile 返回 request.agent.Task，需调用 task.start() 才真正开始上传
   *   3. 必须监听 completed / failed 事件等待上传实际完成
   *
   * @param context 应用上下文
   * @param localPath 本地文件的绝对路径（需在 cacheDir 下，方法内部自动转相对路径）
   * @param cloudPath 云存储目标路径（如 'tracks/xxx/cover.jpg'）
   * @returns 云存储下载 URL；失败返回空字符串
   */
  static async uploadFile(context: common.Context, localPath: string, cloudPath: string): Promise<string> {
    const bucket: cloudStorage.StorageBucket = cloudStorage.bucket();

    // 第一步：检查本地文件是否存在
    try {
      const stat: fileIo.Stat = fileIo.statSync(localPath);
      hilog.info(LOG_DOMAIN, LOG_TAG, '⬆️ Uploading: %{public}s (%{public}dKB) → %{public}s',
        localPath, Math.round(stat.size / 1024), cloudPath);
    } catch (statErr) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '❌ Local file not found: %{public}s', localPath);
      return '';
    }

    // 第二步：将绝对路径转换为相对于 cacheDir 的文件名（SDK 要求）
    const cachePrefix: string = context.cacheDir + '/';
    let relativeLocalPath: string = localPath;
    if (localPath.startsWith(cachePrefix)) {
      relativeLocalPath = localPath.substring(cachePrefix.length);
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, 'SDK localPath (relative): %{public}s', relativeLocalPath);

    // 第三步：通过 Task-based API 上传文件（与官方示例一致）
    try {
      const uploadTask: request.agent.Task = await bucket.uploadFile(context, {
        localPath: relativeLocalPath,
        cloudPath: cloudPath,
        mode: request.agent.Mode.BACKGROUND
      });

      // 用 Promise 封装 Task 的 completed / failed 事件，等待上传真正完成
      let resolved: boolean = false;
      const uploadOk: boolean = await new Promise<boolean>((resolve: (value: boolean) => void) => {
        const finish = (success: boolean): void => {
          if (!resolved) {
            resolved = true;
            resolve(success);
          }
        };

        uploadTask.on('completed', (): void => {
          hilog.info(LOG_DOMAIN, LOG_TAG, '✅ Upload task completed: %{public}s', cloudPath);
          finish(true);
        });
        uploadTask.on('failed', (): void => {
          hilog.error(LOG_DOMAIN, LOG_TAG, '❌ Upload task failed: %{public}s', cloudPath);
          finish(false);
        });

        // 超时保护（90 秒）
        setTimeout((): void => {
          hilog.warn(LOG_DOMAIN, LOG_TAG, '⚠️ Upload task timeout (90s): %{public}s', cloudPath);
          finish(false);
        }, 90000);

        // 启动上传任务
        uploadTask.start((err: BusinessError): void => {
          if (err) {
            hilog.error(LOG_DOMAIN, LOG_TAG, '❌ Task start error: code=%{public}d, msg=%{public}s',
              err.code, err.message);
            finish(false);
          } else {
            hilog.info(LOG_DOMAIN, LOG_TAG, 'Upload task started: %{public}s', cloudPath);
          }
        });
      });

      if (!uploadOk) {
        return '';
      }

      // 上传完成后清理缓存文件
      try {
        fileIo.unlinkSync(localPath);
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Cache file cleaned: %{public}s', relativeLocalPath);
      } catch (cleanErr) {
        // 清理失败不影响主流程
      }
    } catch (uploadErr) {
      const ue = uploadErr as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, '❌ uploadFile failed [%{public}s]: code=%{public}d, msg=%{public}s',
        cloudPath, ue.code || 0, ue.message || '');
      return '';
    }

    // 第四步：获取下载 URL（含重试，文件刚上传可能需要短暂等待）
    for (let retry = 0; retry < 3; retry++) {
      try {
        if (retry > 0) {
          const delayMs: number = 2000 * retry;
          await new Promise<void>((resolve: (value: void) => void) => {
            setTimeout((): void => { resolve(undefined); }, delayMs);
          });
          hilog.info(LOG_DOMAIN, LOG_TAG, 'Retry getDownloadURL (%{public}d/3): %{public}s', retry + 1, cloudPath);
        }
        const downloadUrl: string = await bucket.getDownloadURL(cloudPath);
        hilog.info(LOG_DOMAIN, LOG_TAG, '✅ getDownloadURL: %{public}s', downloadUrl);
        return downloadUrl;
      } catch (urlErr) {
        const uerr = urlErr as BusinessError;
        hilog.warn(LOG_DOMAIN, LOG_TAG, '⚠️ getDownloadURL attempt %{public}d failed [%{public}s]: code=%{public}d, msg=%{public}s',
          retry + 1, cloudPath, uerr.code || 0, uerr.message || '');
      }
    }
    // 3 次都失败，文件已上传但拿不到 URL
    hilog.warn(LOG_DOMAIN, LOG_TAG, '⚠️ getDownloadURL all retries failed, file uploaded but URL unavailable');
    return '';
  }

  // ==================== 业务级上传 ====================

  /**
   * 上传用户头像（自动压缩）
   * - 上传到 users/{userId}/avatar.jpg
   * @returns 云存储下载 URL；失败返回空字符串
   */
  static async uploadUserAvatar(context: common.Context, userId: string, localPath: string): Promise<string> {
    if (userId.length === 0) {
      return '';
    }
    const cacheName = 'avatar_upload_' + userId + '.jpg';
    const compressedPath: string = await CloudStorageService.compressAndCropAvatarToCache(context, localPath, cacheName);
    if (compressedPath.length === 0) {
      return '';
    }
    const cloudPath = 'users/' + userId + '/avatar.jpg';
    const url: string = await CloudStorageService.uploadFile(context, compressedPath, cloudPath);
    return url;
  }

  /**
   * 上传轨迹封面图（自动压缩）
   * - 如果已经是云端 URL，直接返回
   * - 压缩图片到缓存后上传
   * - 上传到 tracks/{trackId}/cover.jpg
   * @returns 云存储下载 URL；上传失败则保留原本地路径
   */
  static async uploadTrackCover(context: common.Context, trackId: string, localPath: string): Promise<string> {
    if (!CloudStorageService.isLocalPath(localPath)) {
      return localPath; // 已经是云端 URL，无需上传
    }

    // 压缩图片到缓存
    const cacheName = 'cover_upload_' + trackId + '.jpg';
    const compressedPath: string = await CloudStorageService.compressImageToCache(context, localPath, cacheName);
    if (compressedPath.length === 0) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '⚠️ Cover compress failed, keep local path');
      return localPath;
    }

    const cloudPath = 'tracks/' + trackId + '/cover.jpg';
    const url: string = await CloudStorageService.uploadFile(context, compressedPath, cloudPath);
    return url.length > 0 ? url : localPath;
  }

  /**
   * 批量上传打卡点图片
   * - 遍历 imageUris JSON 数组中的每个 URI
   * - 跳过已经是云端 URL 的
   * - 上传到 tracks/{trackId}/tombs/{tombId}/{index}.{ext}
   * @param imageUrisJson JSON 数组字符串 '["uri1","uri2"]'
   * @returns 替换后的 JSON 数组字符串（本地 URI 替换为云端 URL）
   */
  static async uploadSpotImages(
    context: common.Context,
    trackId: string,
    tombId: string,
    imageUrisJson: string
  ): Promise<string> {
    if (imageUrisJson.length === 0 || imageUrisJson === '[]') {
      return imageUrisJson;
    }

    let uris: string[];
    try {
      uris = JSON.parse(imageUrisJson) as string[];
    } catch (e) {
      return imageUrisJson;
    }

    if (uris.length === 0) {
      return imageUrisJson;
    }

    let changed = false;
    const updatedUris: string[] = [];

    for (let i = 0; i < uris.length; i++) {
      const uri = uris[i];

      if (!CloudStorageService.isLocalPath(uri)) {
        updatedUris.push(uri); // 已是云端 URL
        continue;
      }

      // 需要上传：先压缩到缓存再上传
      const cacheName = 'spot_' + tombId + '_' + i.toString() + '.jpg';
      const compressedPath: string = await CloudStorageService.compressImageToCache(context, uri, cacheName);
      if (compressedPath.length === 0) {
        updatedUris.push(uri); // 压缩失败，保留原 URI
        continue;
      }

      const cloudPath = 'tracks/' + trackId + '/tombs/' + tombId + '/' + i.toString() + '.jpg';
      const cloudUrl: string = await CloudStorageService.uploadFile(context, compressedPath, cloudPath);

      if (cloudUrl.length > 0) {
        updatedUris.push(cloudUrl);
        changed = true;
      } else {
        updatedUris.push(uri); // 上传失败，保留原 URI
      }
    }

    if (changed) {
      return JSON.stringify(updatedUris);
    }
    return imageUrisJson;
  }

  /**
   * 从网络 URL 下载图片到应用缓存目录（用于重装后恢复打卡点图片）
   * @param context 上下文（用于 cacheDir）
   * @param imageUrl 图片 URL（http/https）
   * @param fileName 缓存文件名，如 restore_spot_xxx_0.jpg
   * @returns 本地路径，失败返回空字符串
   */
  static async downloadImageUrlToCache(
    context: common.Context,
    imageUrl: string,
    fileName: string
  ): Promise<string> {
    if (imageUrl.length === 0 || !imageUrl.startsWith('http')) {
      return '';
    }
    try {
      const httpReq = http.createHttp();
      const resp = await httpReq.request(imageUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      const data = resp.result as ArrayBuffer;
      httpReq.destroy();
      if (!data || data.byteLength === 0) {
        return '';
      }
      const cacheDir: string = context.cacheDir;
      const destPath: string = cacheDir + '/' + fileName;
      const f: fileIo.File = fileIo.openSync(destPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, data);
      fileIo.closeSync(f);
      hilog.info(LOG_DOMAIN, LOG_TAG, '✅ downloadImageUrlToCache: %{public}s', fileName);
      return destPath;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(LOG_DOMAIN, LOG_TAG, '⚠️ downloadImageUrlToCache failed [%{public}s]: %{public}s',
        fileName, err.message || '');
      return '';
    }
  }

  /**
   * 将打卡点 imageUris 中的云端 URL 下载到本地缓存，返回新的 JSON 字符串（用于重装恢复）
   * 已是本地路径的项保持不变；云端 URL 下载后替换为本地路径
   */
  static async restoreSpotImagesToLocal(
    context: common.Context,
    tombId: string,
    imageUrisJson: string
  ): Promise<string> {
    if (imageUrisJson.length === 0 || imageUrisJson === '[]') {
      return imageUrisJson;
    }
    let uris: string[];
    try {
      uris = JSON.parse(imageUrisJson) as string[];
    } catch (e) {
      return imageUrisJson;
    }
    if (uris.length === 0) {
      return imageUrisJson;
    }
    const result: string[] = [];
    for (let i = 0; i < uris.length; i++) {
      const uri = uris[i];
      if (CloudStorageService.isLocalPath(uri)) {
        result.push(uri);
        continue;
      }
      const fileName = 'restore_spot_' + tombId + '_' + i.toString() + '.jpg';
      const localPath: string = await CloudStorageService.downloadImageUrlToCache(context, uri, fileName);
      if (localPath.length > 0) {
        result.push(localPath);
      } else {
        result.push(uri);
      }
    }
    return JSON.stringify(result);
  }

  // ==================== 删除 / 查询 ====================

  /**
   * 删除云存储文件
   */
  static async deleteFile(cloudPath: string): Promise<boolean> {
    try {
      const bucket: cloudStorage.StorageBucket = cloudStorage.bucket();
      await bucket.deleteFile(cloudPath);
      hilog.info(LOG_DOMAIN, LOG_TAG, '✅ File deleted: %{public}s', cloudPath);
      return true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, '❌ Delete file failed [%{public}s]: code=%{public}d, msg=%{public}s',
        cloudPath, err.code || 0, err.message || '');
      return false;
    }
  }

  /**
   * 获取文件下载 URL
   */
  static async getDownloadURL(cloudPath: string): Promise<string> {
    try {
      const bucket: cloudStorage.StorageBucket = cloudStorage.bucket();
      const url: string = await bucket.getDownloadURL(cloudPath);
      return url;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, '❌ getDownloadURL failed [%{public}s]: code=%{public}d, msg=%{public}s',
        cloudPath, err.code || 0, err.message || '');
      return '';
    }
  }

  /**
   * 删除轨迹封面云存储文件
   * 调用场景：删除轨迹时清理云存储
   */
  static async deleteTrackCover(trackId: string): Promise<void> {
    const cloudPath = 'tracks/' + trackId + '/cover.jpg';
    await CloudStorageService.deleteFile(cloudPath);
  }

  /**
   * 删除轨迹相关的所有云存储文件（封面 + 指定打卡点图片）
   * @param trackId 轨迹 ID
   * @param tombIds 打卡点 ID 列表（用于拼接图片路径）
   * @param maxImagesPerSpot 每个打卡点最大图片数（默认 9）
   */
  static async deleteTrackFiles(trackId: string, tombIds?: string[], maxImagesPerSpot?: number): Promise<void> {
    try {
      // 1. 删除封面
      await CloudStorageService.deleteTrackCover(trackId);

      // 2. 删除各打卡点图片（按路径约定逐个尝试删除）
      if (tombIds) {
        const maxImg: number = maxImagesPerSpot || 9;
        for (let t = 0; t < tombIds.length; t++) {
          const tombId: string = tombIds[t];
          for (let i = 0; i < maxImg; i++) {
            const jpgPath = 'tracks/' + trackId + '/tombs/' + tombId + '/' + i.toString() + '.jpg';
            try {
              const bucket: cloudStorage.StorageBucket = cloudStorage.bucket();
              await bucket.deleteFile(jpgPath);
            } catch (delErr) {
              // 文件不存在则跳过（后续索引也不再有）
              break;
            }
          }
        }
      }

      hilog.info(LOG_DOMAIN, LOG_TAG, '✅ Track files cleaned: %{public}s', trackId);
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(LOG_DOMAIN, LOG_TAG, '⚠️ Delete track files failed: %{public}s', err.message || '');
    }
  }
}
