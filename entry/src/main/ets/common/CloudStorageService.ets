import { cloudStorage } from '@kit.CloudFoundationKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'CloudStorageService';

/** 图片压缩最长边（像素），超过则等比缩放 */
const IMAGE_MAX_SIDE = 1920;
/** 图片压缩 JPEG 质量（1-100） */
const IMAGE_JPEG_QUALITY = 75;

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
      const compressedData: ArrayBuffer = await packer.packing(pixelMap, packOpts);

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

  // ==================== 核心上传 ====================

  /**
   * 上传本地文件到云存储，返回下载 URL
   * @param context 应用上下文
   * @param localPath 本地文件的绝对路径（不是 URI，需先 copyUriToCache）
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

    // 第二步：上传文件
    try {
      await bucket.uploadFile(context, {
        localPath: localPath,
        cloudPath: cloudPath
      });
      hilog.info(LOG_DOMAIN, LOG_TAG, '✅ uploadFile completed: %{public}s', cloudPath);
    } catch (uploadErr) {
      const ue = uploadErr as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, '❌ uploadFile failed [%{public}s]: code=%{public}d, msg=%{public}s',
        cloudPath, ue.code || 0, ue.message || '');
      return '';
    }

    // 第三步：获取下载 URL
    try {
      const downloadUrl: string = await bucket.getDownloadURL(cloudPath);
      hilog.info(LOG_DOMAIN, LOG_TAG, '✅ getDownloadURL: %{public}s', downloadUrl);
      return downloadUrl;
    } catch (urlErr) {
      const uerr = urlErr as BusinessError;
      hilog.warn(LOG_DOMAIN, LOG_TAG, '⚠️ getDownloadURL failed [%{public}s]: code=%{public}d, msg=%{public}s',
        cloudPath, uerr.code || 0, uerr.message || '');
      // 获取 URL 失败，返回空字符串（不保存无效路径，下次同步会重试）
      return '';
    }
  }

  // ==================== 业务级上传 ====================

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
