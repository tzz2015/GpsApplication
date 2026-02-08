import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const PREF_NAME = 'auth_prefs';
const KEY_USER = 'current_user';

/**
 * 用户信息接口，与云数据库 User 对齐
 */
export interface AuthUser {
  userId: string;
  displayName: string;
  avatarUrl: string;
  familyName: string;
  signature: string;
  createdAt: number;
  updatedAt: number;
}

/**
 * 用户信息更新入参：所有字段可选
 */
export interface AuthUserUpdate {
  displayName?: string;
  avatarUrl?: string;
  familyName?: string;
  signature?: string;
}

/**
 * 用户认证本地存储
 * 管理当前登录用户信息的持久化
 */
export class AuthStore {
  /**
   * 保存当前登录用户
   */
  static async setUser(context: common.Context, user: AuthUser): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      await prefs.put(KEY_USER, JSON.stringify(user));
      await prefs.flush();
    } catch (e) {
      console.error('AuthStore setUser error: ' + JSON.stringify(e));
    }
  }

  /**
   * 获取当前登录用户
   */
  static async getCurrentUser(context: common.Context): Promise<AuthUser | null> {
    try {
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      const json = await prefs.get(KEY_USER, '') as string;
      if (json.length === 0) {
        return null;
      }
      return JSON.parse(json) as AuthUser;
    } catch (e) {
      console.error('AuthStore getCurrentUser error: ' + JSON.stringify(e));
      return null;
    }
  }

  /**
   * 更新用户部分字段
   */
  static async updateUser(context: common.Context, updates: AuthUserUpdate): Promise<void> {
    try {
      const user = await AuthStore.getCurrentUser(context);
      if (!user) {
        return;
      }
      const updatedUser: AuthUser = {
        userId: user.userId,
        displayName: updates.displayName !== undefined ? updates.displayName : user.displayName,
        avatarUrl: updates.avatarUrl !== undefined ? updates.avatarUrl : user.avatarUrl,
        familyName: updates.familyName !== undefined ? updates.familyName : user.familyName,
        signature: updates.signature !== undefined ? updates.signature : user.signature,
        createdAt: user.createdAt,
        updatedAt: Date.now()
      };
      await AuthStore.setUser(context, updatedUser);
    } catch (e) {
      console.error('AuthStore updateUser error: ' + JSON.stringify(e));
    }
  }

  /**
   * 判断是否已登录
   */
  static async isLoggedIn(context: common.Context): Promise<boolean> {
    const user = await AuthStore.getCurrentUser(context);
    return user !== null && user.userId.length > 0;
  }

  /**
   * 清除登录状态
   */
  static async clearUser(context: common.Context): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      await prefs.delete(KEY_USER);
      await prefs.flush();
    } catch (e) {
      console.error('AuthStore clearUser error: ' + JSON.stringify(e));
    }
  }

  /**
   * 创建新用户（首次登录时调用）
   */
  static createNewUser(userId: string, displayName: string, avatarUrl: string): AuthUser {
    const now = Date.now();
    const user: AuthUser = {
      userId: userId,
      displayName: displayName,
      avatarUrl: avatarUrl,
      familyName: '',
      signature: '',
      createdAt: now,
      updatedAt: now
    };
    return user;
  }
}
