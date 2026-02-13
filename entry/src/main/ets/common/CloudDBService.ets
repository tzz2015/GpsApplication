import { cloudDatabase, cloudCommon } from '@kit.CloudFoundationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import auth from '@hw-agconnect/auth';
import { AuthUser } from '@hw-agconnect/auth';
import { UserEntity } from '../model/UserEntity';
import { TrackEntity } from '../model/TrackEntity';
import { TrackPointEntity } from '../model/TrackPointEntity';
import { TombSpotEntity } from '../model/TombSpotEntity';
import { PostEntity } from '../model/PostEntity';
import { Config } from './Config';
import { TestEnvStore } from './TestEnvStore';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'CloudDBService';

/**
 * Cloud DB 操作服务
 * 封装对 AGC 云数据库的 CRUD 操作
 * 使用 Cloud Foundation Kit (@kit.CloudFoundationKit)
 */
export class CloudDBService {
  /** 懒加载数据库 Zone 实例，避免模块级初始化时 AGC 未就绪 */
  private static _zone: cloudDatabase.DatabaseZone | null = null;
  private static _zoneName: string = '';

  static getCurrentZoneName(): string {
    return TestEnvStore.isUseTestDataSync() ? Config.CLOUD_DB_ZONE_TEST : Config.CLOUD_DB_ZONE_PROD;
  }

  static resetZoneCache(): void {
    CloudDBService._zone = null;
    CloudDBService._zoneName = '';
  }

  private static getZone(): cloudDatabase.DatabaseZone {
    const zoneName = CloudDBService.getCurrentZoneName();
    if (!CloudDBService._zone || CloudDBService._zoneName !== zoneName) {
      try {
        CloudDBService._zone = cloudDatabase.zone(zoneName);
        CloudDBService._zoneName = zoneName;
        hilog.info(LOG_DOMAIN, LOG_TAG, '[OK] Database zone initialized: %{public}s', zoneName);
      } catch (e) {
        const err = e as BusinessError;
        hilog.error(LOG_DOMAIN, LOG_TAG, '[ERR] Database zone init FAILED: code=%{public}d, msg=%{public}s',
          err.code, err.message);
        throw new Error('Database zone init failed: ' + err.message);
      }
    }
    return CloudDBService._zone;
  }

  /**
   * 是否已有 AGC Auth 登录态（Cloud DB 写入需 Authenticated 权限时必用）
   */
  static async hasAgcAuthUser(): Promise<boolean> {
    try {
      const user: AuthUser | null = await auth.getCurrentUser();
      return user !== null;
    } catch (e) {
      return false;
    }
  }

  /**
   * 确保 AGC Auth 已登录并注册 AuthProvider
   * 无用户时会尝试 HWID 静默登录；若仍无用户则返回 false（关闭 World 权限时无法写入 Cloud DB）
   */
  static async ensureAuth(): Promise<boolean> {
    try {
      let user: AuthUser | null = await auth.getCurrentUser();
      if (user === null) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'No AGC Auth user, trying HWID signIn...');
        try {
          await auth.signIn({
            autoCreateUser: true,
            credentialInfo: { 'kind': 'hwid' }
          });
          hilog.info(LOG_DOMAIN, LOG_TAG, '[OK] AGC Auth signIn success');
          user = await auth.getCurrentUser();
        } catch (signErr) {
          const se = signErr as BusinessError;
          hilog.warn(LOG_DOMAIN, LOG_TAG, '[WARN] AGC Auth signIn failed: code=%{public}d', se.code || 0);
        }
      }
      if (user !== null) {
        hilog.info(LOG_DOMAIN, LOG_TAG, '[OK] AGC Auth user exists, uid=%{public}s', user.getUid());
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[WARN] getCurrentUser failed: code=%{public}d', err.code || 0);
    }

    try {
      cloudCommon.init({ authProvider: auth.getAuthProvider() });
      hilog.info(LOG_DOMAIN, LOG_TAG, '[OK] CloudCommon AuthProvider registered');
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[WARN] cloudCommon.init skipped');
    }

    const hasUser = await CloudDBService.hasAgcAuthUser();
    if (!hasUser) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[WARN] AGC Auth 未登录，Cloud DB 写入将无权限（请关闭 World 时先登录）');
    }
    return hasUser;
  }

  /**
   * 诊断方法：测试 AGC Auth 状态 + Cloud DB 连通性
   * 在个人中心调用，日志输出到 HiLog（搜索 TAG: CloudDBService）
   */
  static async diagnose(): Promise<string> {
    const results: string[] = [];

    hilog.info(LOG_DOMAIN, LOG_TAG, '====== Cloud DB 诊断开始 ======');

    // ★ 第 0a 步：HTTP 连通性测试（直接测 AGC 网关 DNS）
    const testUrls: string[] = [
      'https://connect-drcn.dbankcloud.cn',
      'https://connect-drcn.hispace.hicloud.com',
      'https://www.baidu.com'
    ];
    for (let i = 0; i < testUrls.length; i++) {
      const testUrl = testUrls[i];
      try {
        const httpRequest = http.createHttp();
        const resp = await httpRequest.request(testUrl, {
          method: http.RequestMethod.GET,
          connectTimeout: 5000,
          readTimeout: 5000
        });
        const code = resp.responseCode;
        results.push('[OK] HTTP ' + testUrl + ' → ' + code.toString());
        hilog.info(LOG_DOMAIN, LOG_TAG, '[OK] [0a] HTTP %{public}s → %{public}d', testUrl, code);
        httpRequest.destroy();
      } catch (httpErr) {
        const he = httpErr as BusinessError;
        results.push('[ERR] HTTP ' + testUrl + ' → code=' + (he.code || 0).toString());
        hilog.error(LOG_DOMAIN, LOG_TAG, '[ERR] [0a] HTTP %{public}s → code=%{public}d, msg=%{public}s',
          testUrl, he.code || 0, he.message || '');
      }
    }

    // ★ 第 0b 步：检查 AGC Auth 状态
    try {
      const user: AuthUser | null = await auth.getCurrentUser();
      if (user !== null) {
        const uid: string = user.getUid();
        const displayName: string = user.getDisplayName();
        results.push('[OK] AGC Auth 已登录: uid=' + uid + ', name=' + displayName);
        hilog.info(LOG_DOMAIN, LOG_TAG, '[OK] [0b] AGC Auth 已登录: uid=%{public}s, name=%{public}s',
          uid, displayName);
      } else {
        results.push('[WARN] AGC Auth 未登录');
        hilog.warn(LOG_DOMAIN, LOG_TAG, '[WARN] [0b] AGC Auth 未登录');

        // 尝试 HWID 登录
        try {
          const signInResult = await auth.signIn({
            autoCreateUser: true,
            credentialInfo: { 'kind': 'hwid' }
          });
          const signedUser: AuthUser = signInResult.getUser();
          results.push('[OK] HWID 登录成功: uid=' + signedUser.getUid());
          hilog.info(LOG_DOMAIN, LOG_TAG, '[OK] [0b] HWID 登录成功: uid=%{public}s', signedUser.getUid());
        } catch (signErr) {
          const se = signErr as BusinessError;
          results.push('[ERR] HWID 登录失败: code=' + (se.code || 0).toString());
          hilog.error(LOG_DOMAIN, LOG_TAG, '[ERR] [0b] HWID 登录失败: code=%{public}d, msg=%{public}s',
            se.code || 0, se.message || '');

          // ★ 再尝试匿名登录
          try {
            const anonResult = await auth.signInAnonymously();
            const anonUser: AuthUser = anonResult.getUser();
            results.push('[OK] 匿名登录成功: uid=' + anonUser.getUid());
            hilog.info(LOG_DOMAIN, LOG_TAG, '[OK] [0b] 匿名登录成功: uid=%{public}s', anonUser.getUid());
          } catch (anonErr) {
            const ae = anonErr as BusinessError;
            results.push('[ERR] 匿名登录也失败: code=' + (ae.code || 0).toString());
            hilog.error(LOG_DOMAIN, LOG_TAG, '[ERR] [0b] 匿名登录失败: code=%{public}d, msg=%{public}s',
              ae.code || 0, ae.message || '');
          }
        }
      }
    } catch (e) {
      const err = e as BusinessError;
      results.push('[ERR] getCurrentUser 失败: code=' + (err.code || 0).toString());
      hilog.error(LOG_DOMAIN, LOG_TAG, '[ERR] [0b] getCurrentUser 失败: code=%{public}d', err.code || 0);
    }

    // ★ 第 1 步：注册 AuthProvider
    try {
      cloudCommon.init({ authProvider: auth.getAuthProvider() });
      results.push('[OK] CloudCommon AuthProvider 已注册');
      hilog.info(LOG_DOMAIN, LOG_TAG, '[OK] [1/5] CloudCommon AuthProvider 已注册');
    } catch (e) {
      const err = e as BusinessError;
      results.push('[ERR] CloudCommon init 失败: ' + (err.message || ''));
      hilog.error(LOG_DOMAIN, LOG_TAG, '[ERR] [1/5] CloudCommon init 失败: %{public}s', err.message || '');
    }

    // 2. 测试 Zone 初始化
    try {
      // 重置 zone 以重新获取（带上新的 AuthProvider）
      CloudDBService.resetZoneCache();
      CloudDBService.getZone();
      results.push('[OK] Zone "' + CloudDBService.getCurrentZoneName() + '" 初始化成功');
      hilog.info(LOG_DOMAIN, LOG_TAG, '[OK] [2/5] Zone 初始化成功');
    } catch (e) {
      const err = e as BusinessError;
      results.push('[ERR] Zone 初始化失败: code=' + (err.code || 0).toString() + ', ' + (err.message || ''));
      hilog.error(LOG_DOMAIN, LOG_TAG, '[ERR] [2/5] Zone 初始化失败: code=%{public}d, msg=%{public}s',
        err.code || 0, err.message || '');
      hilog.info(LOG_DOMAIN, LOG_TAG, '====== Cloud DB 诊断结束 ======');
      return results.join('\n');
    }

    // 3. 测试写入（upsert 一条测试用户）
    try {
      const testUser = new UserEntity();
      testUser.userId = '__diag_test__';
      testUser.nickname = 'DiagTest';
      testUser.createdAt = new Date();
      testUser.updatedAt = new Date();

      const count = await CloudDBService.getZone().upsert(testUser);
      results.push('[OK] 写入测试成功, count=' + count.toString());
      hilog.info(LOG_DOMAIN, LOG_TAG, '[OK] [3/5] upsert 测试成功, count=%{public}d', count);
    } catch (e) {
      const err = e as BusinessError;
      results.push('[ERR] 写入失败: code=' + (err.code || 0).toString() + ', ' + (err.message || ''));
      hilog.error(LOG_DOMAIN, LOG_TAG, '[ERR] [3/5] upsert 失败: code=%{public}d, msg=%{public}s',
        err.code || 0, err.message || '');
    }

    // 4. 测试查询
    try {
      const condition = new cloudDatabase.DatabaseQuery(UserEntity);
      condition.equalTo('userId', '__diag_test__');
      const result: UserEntity[] = await CloudDBService.getZone().query(condition);
      results.push('[OK] 查询测试成功, 返回 ' + result.length.toString() + ' 条');
      hilog.info(LOG_DOMAIN, LOG_TAG, '[OK] [4/5] query 测试成功, count=%{public}d', result.length);
    } catch (e) {
      const err = e as BusinessError;
      results.push('[ERR] 查询失败: code=' + (err.code || 0).toString() + ', ' + (err.message || ''));
      hilog.error(LOG_DOMAIN, LOG_TAG, '[ERR] [4/5] query 失败: code=%{public}d, msg=%{public}s',
        err.code || 0, err.message || '');
    }

    // 5. 清理测试数据
    try {
      const testUser = new UserEntity();
      testUser.userId = '__diag_test__';
      await CloudDBService.getZone().delete(testUser);
      results.push('[OK] 清理测试数据成功');
      hilog.info(LOG_DOMAIN, LOG_TAG, '[OK] [5/5] 清理测试数据成功');
    } catch (e) {
      const err = e as BusinessError;
      results.push('[WARN] 清理失败(可忽略): ' + (err.message || ''));
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[WARN] [5/5] 清理失败: %{public}s', err.message || '');
    }

    hilog.info(LOG_DOMAIN, LOG_TAG, '====== Cloud DB 诊断结束 ======');
    return results.join('\n');
  }

  // ==================== User 操作 ====================

  /**
   * 上传/更新用户信息
   */
  static async upsertUser(user: UserEntity): Promise<number> {
    try {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Upsert user: userId=%{public}s', user.userId || 'null');
      const count = await CloudDBService.getZone().upsert(user);
      hilog.info(LOG_DOMAIN, LOG_TAG, '[OK] Upsert user success, count: %{public}d', count);
      return count;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, '[ERR] Upsert user failed: code=%{public}d, msg=%{public}s',
        err.code, err.message);
      return 0;
    }
  }

  /**
   * 查询用户信息
   */
  static async queryUser(userId: string): Promise<UserEntity | null> {
    try {
      const condition = new cloudDatabase.DatabaseQuery(UserEntity);
      condition.equalTo('userId', userId);
      const result: UserEntity[] = await CloudDBService.getZone().query(condition);
      if (result && result.length > 0) {
        return result[0];
      }
      return null;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Query user failed: %{public}s', err.message);
      return null;
    }
  }

  // ==================== Track 操作 ====================

  /**
   * 上传/更新轨迹
   */
  static async upsertTrack(track: TrackEntity): Promise<number> {
    try {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Upsert track: id=%{public}s, title=%{public}s',
        track.trackId || 'null', track.title || 'null');
      const count = await CloudDBService.getZone().upsert(track);
      hilog.info(LOG_DOMAIN, LOG_TAG, '[OK] Upsert track success, count: %{public}d', count);
      return count;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, '[ERR] Upsert track failed: code=%{public}d, msg=%{public}s',
        err.code, err.message);
      return 0;
    }
  }

  /**
   * 查询指定用户的所有轨迹
   */
  static async queryTracksByUser(userId: string): Promise<TrackEntity[]> {
    try {
      const condition = new cloudDatabase.DatabaseQuery(TrackEntity);
      condition.equalTo('ownerUserId', userId);
      condition.orderByDesc('createdAt');
      const result: TrackEntity[] = await CloudDBService.getZone().query(condition);
      return result || [];
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Query tracks by user failed: %{public}s', err.message);
      return [];
    }
  }

  /**
   * 查询公开轨迹列表
   */
  static async queryPublicTracks(): Promise<TrackEntity[]> {
    try {
      const condition = new cloudDatabase.DatabaseQuery(TrackEntity);
      condition.equalTo('visibility', 'PUBLIC');
      condition.equalTo('status', 'done');
      condition.orderByDesc('createdAt');
      const result: TrackEntity[] = await CloudDBService.getZone().query(condition);
      return result || [];
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Query public tracks failed: %{public}s', err.message);
      return [];
    }
  }

  /**
   * 根据 trackId 查询轨迹
   */
  static async queryTrackById(trackId: string): Promise<TrackEntity | null> {
    try {
      const condition = new cloudDatabase.DatabaseQuery(TrackEntity);
      condition.equalTo('trackId', trackId);
      const result: TrackEntity[] = await CloudDBService.getZone().query(condition);
      if (result && result.length > 0) {
        return result[0];
      }
      return null;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Query track by id failed: %{public}s', err.message);
      return null;
    }
  }

  /**
   * 删除轨迹
   */
  static async deleteTrack(trackId: string): Promise<number> {
    try {
      const track = new TrackEntity();
      track.trackId = trackId;
      const count = await CloudDBService.getZone().delete(track);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Delete track success, count: %{public}d', count);
      return count;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Delete track failed: %{public}s', err.message);
      return 0;
    }
  }

  // ==================== TrackPoint 操作 ====================

  /**
   * 逐条上传轨迹点
   */
  static async upsertTrackPoints(points: TrackPointEntity[]): Promise<number> {
    let totalCount = 0;
    for (let i = 0; i < points.length; i++) {
      try {
        await CloudDBService.getZone().upsert(points[i]);
        totalCount++;
      } catch (e) {
        const err = e as BusinessError;
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Upsert point %{public}d failed: %{public}s', i, err.message);
      }
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Upsert track points done, count: %{public}d/%{public}d', totalCount, points.length);
    return totalCount;
  }

  /**
   * 查询指定轨迹的所有轨迹点
   */
  static async queryTrackPoints(trackId: string): Promise<TrackPointEntity[]> {
    try {
      const condition = new cloudDatabase.DatabaseQuery(TrackPointEntity);
      condition.equalTo('trackId', trackId);
      condition.orderByAsc('orderIndex');
      const result: TrackPointEntity[] = await CloudDBService.getZone().query(condition);
      return result || [];
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Query track points failed: %{public}s', err.message);
      return [];
    }
  }

  /**
   * 删除指定轨迹的所有轨迹点
   */
  static async deleteTrackPoints(trackId: string): Promise<void> {
    try {
      const points = await CloudDBService.queryTrackPoints(trackId);
      for (let i = 0; i < points.length; i++) {
        await CloudDBService.getZone().delete(points[i]);
      }
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Delete track points success for track: %{public}s', trackId);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Delete track points failed: %{public}s', err.message);
    }
  }

  // ==================== TombSpot 操作 ====================

  /**
   * 上传/更新打卡点
   * 确保 contentText/imageUris 必为字符串，避免 Cloud DB 未持久化空/undefined
   */
  static async upsertTombSpot(spot: TombSpotEntity): Promise<number> {
    try {
      if (spot.contentText === undefined || spot.contentText === null) {
        spot.contentText = '';
      }
      if (spot.imageUris === undefined || spot.imageUris === null) {
        spot.imageUris = '[]';
      }
      const count = await CloudDBService.getZone().upsert(spot);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Upsert tomb spot success, count: %{public}d, contentLen: %{public}d, imageLen: %{public}d',
        count, (spot.contentText || '').length, (spot.imageUris || '').length);
      return count;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Upsert tomb spot failed: %{public}s', err.message);
      return 0;
    }
  }

  /**
   * 查询指定轨迹的所有打卡点
   */
  static async queryTombSpots(trackId: string): Promise<TombSpotEntity[]> {
    try {
      const condition = new cloudDatabase.DatabaseQuery(TombSpotEntity);
      condition.equalTo('trackId', trackId);
      condition.orderByAsc('orderIndex');
      const result: TombSpotEntity[] = await CloudDBService.getZone().query(condition);
      return result || [];
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Query tomb spots failed: %{public}s', err.message);
      return [];
    }
  }

  /**
   * 删除打卡点
   */
  static async deleteTombSpot(tombId: string): Promise<number> {
    try {
      const spot = new TombSpotEntity();
      spot.tombId = tombId;
      const count = await CloudDBService.getZone().delete(spot);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Delete tomb spot success, count: %{public}d', count);
      return count;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Delete tomb spot failed: %{public}s', err.message);
      return 0;
    }
  }

  // ==================== Post 操作 ====================

  /**
   * 上传/更新图文
   */
  static async upsertPost(post: PostEntity): Promise<number> {
    try {
      const count = await CloudDBService.getZone().upsert(post);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Upsert post success, count: %{public}d', count);
      return count;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Upsert post failed: %{public}s', err.message);
      return 0;
    }
  }

  /**
   * 查询指定打卡点的图文列表
   */
  static async queryPostsByTombSpot(tombId: string): Promise<PostEntity[]> {
    try {
      const condition = new cloudDatabase.DatabaseQuery(PostEntity);
      condition.equalTo('tombId', tombId);
      condition.orderByDesc('createdAt');
      const result: PostEntity[] = await CloudDBService.getZone().query(condition);
      return result || [];
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Query posts failed: %{public}s', err.message);
      return [];
    }
  }

  /**
   * 删除图文
   */
  static async deletePost(postId: string): Promise<number> {
    try {
      const post = new PostEntity();
      post.postId = postId;
      const count = await CloudDBService.getZone().delete(post);
      return count;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Delete post failed: %{public}s', err.message);
      return 0;
    }
  }
}
