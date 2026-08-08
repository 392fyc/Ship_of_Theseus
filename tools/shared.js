/**
 * Ship of Theseus — 设计工具共享组件
 * ====================================
 * 所有设计工具（天赋树/装备/地图/伤害模拟器）的共享常量、数据结构和工具函数。
 * 各工具通过 <script src="shared.js"> 引入，获取统一的游戏数据定义。
 *
 * 用途：
 * 1. 统一游戏常量（地形、属性、稀有度等），避免各工具各自定义造成不一致
 * 2. 提供跨工具数据接口，未来可直接互通数据（如装备设计器数据给伤害模拟器用）
 * 3. 通用工具函数（localStorage管理、JSON导入导出、toast提示等）
 */

// ============================================================
// 版本
// ============================================================
const SHARED_VERSION = '1.0.0';

// ============================================================
// 游戏常量 — 地形系统
// ============================================================

const TERRAIN_TYPES = {
  PLAIN:         { id: 0, name: '平地',   moveCost: 1, passable: true,  blocksLOS: false, color: '#c8d6a0', effect: '无' },
  FOREST:        { id: 1, name: '树林',   moveCost: 2, passable: true,  blocksLOS: false, color: '#2d6a4f', effect: '+闪避' },
  MOUNTAIN:      { id: 2, name: '山地',   moveCost: 2, passable: true,  blocksLOS: false, color: '#8d6e63', effect: '+防御, +魔防' },
  PEAK:          { id: 3, name: '山峰',   moveCost: -1, passable: false, blocksLOS: true,  color: '#5d4037', effect: '不可通行' },
  WALL:          { id: 4, name: '墙壁',   moveCost: -1, passable: false, blocksLOS: false, color: '#455a64', effect: '不可通行' },
  SHALLOW_WATER: { id: 5, name: '浅水',   moveCost: 2, passable: true,  blocksLOS: false, color: '#4fc3f7', effect: '潮湿' },
  DEEP_WATER:    { id: 6, name: '深水',   moveCost: -1, passable: false, blocksLOS: false, color: '#0277bd', effect: '不可通行' },
  LAVA:          { id: 7, name: '熔岩',   moveCost: 2, passable: true,  blocksLOS: false, color: '#ff5722', effect: '燃烧' },
  SWAMP:         { id: 8, name: '毒沼',   moveCost: 3, passable: true,  blocksLOS: false, color: '#7b5e57', effect: '中毒' },
};

// 按ID快速查找
const TERRAIN_BY_ID = Object.values(TERRAIN_TYPES);

// ============================================================
// 游戏常量 — 特殊地形
// ============================================================

const SPECIAL_TERRAIN_TYPES = [
  { id: 'healing_ground', name: '治愈之地', symbol: '✚', color: '#4ecca3', category: 'buff' },
  { id: 'buff_zone',      name: '增益区域', symbol: '▲', color: '#3498db', category: 'buff' },
  { id: 'debuff_zone',    name: '减益区域', symbol: '▼', color: '#e74c3c', category: 'debuff' },
  { id: 'trap',           name: '陷阱',     symbol: '⚡', color: '#f39c12', category: 'trap' },
  { id: 'teleporter',     name: '传送阵',   symbol: '◎', color: '#9b59b6', category: 'teleport' },
];

// ============================================================
// 游戏常量 — 建筑类型
// ============================================================

const BUILDING_TYPES = [
  { id: 'watchtower',  name: '哨塔',   symbol: '🏠', color: '#e67e22', tags: [] },
  { id: 'fortress',    name: '要塞',   symbol: '🏰', color: '#e94560', tags: [] },
  { id: 'barricade',   name: '拒马',   symbol: '⊞',  color: '#95a5a6', tags: [] },
  { id: 'magic_tower', name: '魔法塔', symbol: '🔮', color: '#9b59b6', tags: ['mage'] },
];

// ============================================================
// 游戏常量 — 属性定义
// ============================================================

const STAT_DEFS = {
  hp:    { name: 'HP',    fullName: '生命值',  category: 'vital' },
  atk:   { name: 'ATK',   fullName: '攻击力',  category: 'offense' },
  mag:   { name: 'MAG',   fullName: '魔法攻击', category: 'offense' },
  pdef:  { name: 'P.DEF', fullName: '物理防御', category: 'defense' },
  mdef:  { name: 'M.DEF', fullName: '魔法防御', category: 'defense' },
  hit:   { name: 'HIT',   fullName: '命中',    category: 'accuracy' },
  eva:   { name: 'EVA',   fullName: '闪避',    category: 'accuracy' },
  crit:  { name: 'CRIT',  fullName: '暴击',    category: 'critical' },
  crit_eva: { name: 'C.EVA', fullName: '暴击闪避', category: 'critical' },
  spd:   { name: 'SPD',   fullName: '速度',    category: 'speed' },
  move:  { name: 'MOVE',  fullName: '移动力',  category: 'speed' },
  res:   { name: 'RES',   fullName: '抗性',    category: 'defense' },
};

// 不随等级成长的属性
const NON_GROWING_STATS = ['spd', 'move'];

// ============================================================
// 游戏常量 — 稀有度
// ============================================================

const RARITY_DEFS = {
  common:    { name: '普通', color: '#a0a0a0', order: 0 },
  uncommon:  { name: '精良', color: '#2ecc71', order: 1 },
  rare:      { name: '稀有', color: '#3498db', order: 2 },
  epic:      { name: '史诗', color: '#9b59b6', order: 3 },
  legendary: { name: '传说', color: '#e67e22', order: 4 },
};

// ============================================================
// 游戏常量 — 装备槽位
// ============================================================

// 两槽定稿（2026-07-05 用户裁决 Q7）。原先这里还有 sub_weapon（副手）与
// accessory（饰品）两项 4 槽 Demo 残留，2026-08-08 Wave 2 按定稿清掉。
// 剑圣双持不走通用槽位，是**职业专属特例**——引擎侧实现在 Unit.offhand_weapon_id，
// 不进本枚举，也不进设计库的 EquipSlot。
const EQUIP_SLOTS = {
  weapon: { name: '武器', icon: '⚔' },
  armor:  { name: '护甲', icon: '🛡' },
};

// ============================================================
// 游戏常量 — 武器类型
// ============================================================

const WEAPON_TYPES = {
  sword: { name: '剑',     classes: ['swordsman'], primaryStats: ['atk', 'hit', 'crit'] },
  bow:   { name: '弓',     classes: ['archer'],    primaryStats: ['atk', 'crit'] },
  tome:  { name: '魔法书', classes: ['mage'],      primaryStats: ['mag', 'hit'] },
};

// ============================================================
// 游戏常量 — 伤害/技能类型
// ============================================================

// 2026-07-11 用户裁决：伤害类型轴无 holy，旧 holy（无视防御）语义即 pure
const ELEMENT_TYPES = ['physical', 'magical', 'pure', 'hybrid'];
const ATTACK_TYPES = ['melee', 'ranged', 'area'];

// ============================================================
// 游戏常量 — 天赋节点类型
// ============================================================

const TALENT_NODE_TYPES = {
  active_skill:  { name: 'Active Skill',  color: '#3498db', label: 'Skill' },
  passive:       { name: 'Passive',       color: '#2ecc71', label: 'Passive' },
  trait:         { name: 'Trait',         color: '#9b59b6', label: 'Trait' },
  skill_upgrade: { name: 'Skill Upgrade', color: '#e67e22', label: 'Upgrade' },
  advancement:   { name: 'Advancement',   color: '#e94560', label: 'ADV' },
  gauge_core:    { name: 'Gauge Core',    color: '#f1c40f', label: 'Gauge' },
  gauge_extend:  { name: 'Gauge Extend',  color: '#f39c12', label: 'G.Ext' },
  stat_minor:    { name: 'Stat (minor)',  color: '#7f8c8d', label: 'Stat' },
};

// ============================================================
// 游戏常量 — 装备阶段参考值（用于平衡校验）
// ============================================================

const EQUIPMENT_TIER_REFERENCE = [
  { tier: 1, stage: '初期', levels: '1-5',   weaponAtk: [2, 4],   armorDef: [1, 2],   description: '初始装备' },
  { tier: 2, stage: '中前', levels: '6-10',  weaponAtk: [5, 6],   armorDef: [3, 4],   description: '中期装备' },
  { tier: 3, stage: '中期', levels: '11-15', weaponAtk: [7, 8],   armorDef: [4, 5],   description: '中后期装备' },
  { tier: 4, stage: '后期', levels: '16-20', weaponAtk: [9, 12],  armorDef: [5, 7],   description: '后期装备' },
  { tier: 5, stage: '终盘', levels: '21-25', weaponAtk: [12, 14], armorDef: [7, 8],   description: '终盘装备' },
  { tier: 6, stage: '极限', levels: '26-30', weaponAtk: [14, 18], armorDef: [8, 10],  description: '极限装备' },
];

// ============================================================
// 游戏常量 — 职业基础数据（Lv1）
// ============================================================

const CLASS_BASE_STATS = {
  swordsman: {
    name: '剑士', hp: 90, atk: 14, mag: 5, pdef: 7, mdef: 5,
    hit: 85, eva: 15, crit: 12, crit_eva: 5, spd: 12, move: 3, res: 5,
    growth: { hp: 8, atk: 3, mag: 0, pdef: 1, mdef: 1, hit: 2, eva: 2, crit: 2, crit_eva: 0, res: 0 },
    advancements: {
      sword_saint: { name: '剑圣', growthOverride: { atk: 4, crit: 3 } },
      magic_swordsman: { name: '魔剑士', growthOverride: { atk: 2, mag: 3 } },
    }
  },
  archer: {
    name: '弓箭手', hp: 75, atk: 16, mag: 5, pdef: 5, mdef: 5,
    hit: 78, eva: 12, crit: 14, crit_eva: 3, spd: 10, move: 3, res: 5,
    growth: { hp: 6, atk: 3, mag: 0, pdef: 1, mdef: 1, hit: 2, eva: 2, crit: 3, crit_eva: 0, res: 0 },
    advancements: {
      sniper: { name: '神射手', growthOverride: { atk: 4, hit: 3 } },
      elven_archer: { name: '精灵射手', growthOverride: { eva: 3, crit: 2 } },
    }
  },
  mage: {
    name: '魔法师', hp: 65, atk: 5, mag: 20, pdef: 4, mdef: 10,
    hit: 82, eva: 5, crit: 5, crit_eva: 3, spd: 7, move: 2, res: 10,
    growth: { hp: 5, atk: 0, mag: 4, pdef: 0, mdef: 2, hit: 2, eva: 1, crit: 1, crit_eva: 0, res: 0 },
    advancements: {
      fire_sage: { name: '火之贤者', growthOverride: { mag: 5, crit: 2 } },
      water_sage: { name: '水之贤者', growthOverride: { hp: 6, mdef: 3 } },
    }
  },
};

// ============================================================
// 游戏公式 — 伤害计算
// ============================================================

const GameFormulas = {
  /**
   * 计算属性值（含成长）
   * @param {string} classId - 职业ID
   * @param {number} level - 等级
   * @param {string|null} advancement - 转职ID（null=未转职）
   * @param {number} advLevel - 转职时的等级（默认10）
   */
  calcStats(classId, level, advancement = null, advLevel = 10) {
    const cls = CLASS_BASE_STATS[classId];
    if (!cls) return null;

    const stats = {};
    const allStats = Object.keys(cls.growth);

    for (const stat of allStats) {
      let value = cls[stat] || 0;

      if (NON_GROWING_STATS.includes(stat)) {
        stats[stat] = value;
        continue;
      }

      // 转职前成长
      const preAdvLevels = advancement ? Math.min(level, advLevel) - 1 : level - 1;
      value += cls.growth[stat] * preAdvLevels;

      // 转职后成长（使用覆盖成长率）
      if (advancement && level > advLevel) {
        const adv = cls.advancements[advancement];
        if (adv) {
          const postLevels = level - advLevel;
          const growthRate = adv.growthOverride[stat] !== undefined
            ? adv.growthOverride[stat]
            : cls.growth[stat];
          value += growthRate * postLevels;
        }
      }

      stats[stat] = Math.round(value);
    }

    // 补充非成长属性
    stats.hp = cls.hp + cls.growth.hp * (level - 1);
    stats.spd = cls.spd;
    stats.move = cls.move;

    return stats;
  },

  /**
   * 基础伤害计算
   * physical: ATK - P.DEF (min 0)
   * magical:  MAG - M.DEF (min 0)
   * pure:     无视防御
   * hybrid:   物理与魔法各算一次（各带自己的 min 0 地板）再取算术平均
   *           = ( max(0, ATK - P.DEF) + max(0, MAG - M.DEF) ) / 2
   */
  calcBaseDamage(atk, mag, pdef, mdef, elementType) {
    switch (elementType) {
      case 'physical': return Math.max(0, atk - pdef);
      case 'magical':  return Math.max(0, mag - mdef);
      case 'pure':     return mag; // pure 无视防御（工具简化：按 mag 来源）
      // hybrid：各算一次再平均，不是一次性减平均防御（2026-08-03 用户裁决）
      case 'hybrid':   return (Math.max(0, atk - pdef) + Math.max(0, mag - mdef)) / 2;
      default:         return Math.max(0, atk - pdef);
    }
  },

  /**
   * 命中率计算 (加法模型, 20%-100%)
   */
  calcHitRate(attackerHit, defenderEva, bonuses = 0) {
    return Math.max(20, Math.min(100, attackerHit - defenderEva + bonuses));
  },

  /**
   * 暴击率计算 (0%-50%)
   */
  calcCritRate(attackerCrit, defenderCritEva, bonuses = 0) {
    const raw = (attackerCrit + bonuses - defenderCritEva);
    return Math.max(0, Math.min(50, raw));
  },

  /**
   * 天赋点计算
   * 天赋点 = 等级（Lv1获得1点，起始节点不免费）
   */
  calcTalentPoints(level) {
    return Math.max(0, level);
  },
};

// ============================================================
// 通用工具函数 — localStorage管理
// ============================================================

const StorageHelper = {
  /**
   * 获取某个命名空间下的所有key
   */
  getKeys(namespace) {
    const keys = [];
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      if (k.startsWith(namespace)) {
        keys.push(k.substring(namespace.length));
      }
    }
    return keys;
  },

  /**
   * 安全读取JSON
   */
  getJSON(key, defaultValue = null) {
    try {
      const raw = localStorage.getItem(key);
      return raw ? JSON.parse(raw) : defaultValue;
    } catch (e) {
      console.error('StorageHelper.getJSON error:', key, e);
      return defaultValue;
    }
  },

  /**
   * 安全写入JSON
   */
  setJSON(key, value) {
    try {
      localStorage.setItem(key, JSON.stringify(value));
      return true;
    } catch (e) {
      console.error('StorageHelper.setJSON error:', key, e);
      return false;
    }
  },

  /**
   * 删除
   */
  remove(key) {
    localStorage.removeItem(key);
  },
};

// ============================================================
// 通用工具函数 — JSON导入导出
// ============================================================

const IOHelper = {
  /**
   * 下载JSON文件
   */
  downloadJSON(data, filename) {
    const json = JSON.stringify(data, null, 2);
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
  },

  /**
   * 复制文本到剪贴板
   */
  async copyToClipboard(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch (e) {
      // Fallback: prompt
      prompt('Copy:', text);
      return false;
    }
  },

  /**
   * 从文件输入读取JSON
   * @returns {Promise<object>}
   */
  readJSONFile(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = (e) => {
        try {
          resolve(JSON.parse(e.target.result));
        } catch (err) {
          reject(new Error('Invalid JSON'));
        }
      };
      reader.onerror = () => reject(new Error('File read error'));
      reader.readAsText(file);
    });
  },

  /**
   * 触发文件选择对话框并读取
   * @returns {Promise<object>}
   */
  promptImportJSON() {
    return new Promise((resolve, reject) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = '.json';
      input.onchange = async (e) => {
        const file = e.target.files[0];
        if (!file) { reject(new Error('No file selected')); return; }
        try {
          const data = await this.readJSONFile(file);
          resolve(data);
        } catch (err) {
          reject(err);
        }
      };
      input.click();
    });
  },
};

// ============================================================
// 通用工具函数 — UI辅助
// ============================================================

const UIHelper = {
  /**
   * Toast提示（需要页面中有 #toast 元素）
   */
  toast(msg, duration = 2000) {
    let t = document.getElementById('toast');
    if (!t) {
      t = document.createElement('div');
      t.id = 'toast';
      t.style.cssText = `
        position:fixed;bottom:20px;left:50%;transform:translateX(-50%) translateY(100px);
        background:#0f3460;color:#e0e0e0;padding:10px 24px;border-radius:8px;
        font-size:13px;transition:transform 0.3s;z-index:9999;border:1px solid #1a5276;
      `;
      document.body.appendChild(t);
    }
    t.textContent = msg;
    t.style.transform = 'translateX(-50%) translateY(0)';
    clearTimeout(t._tid);
    t._tid = setTimeout(() => {
      t.style.transform = 'translateX(-50%) translateY(100px)';
    }, duration);
  },
};

// ============================================================
// 跨工具数据接口
// ============================================================

/**
 * 跨工具数据访问层。
 * 各工具可以通过这个接口读取其他工具存储的数据。
 *
 * 用法示例（伤害模拟器读取装备设计器数据）：
 *   const weapons = CrossToolData.getEquipments('weapon');
 *   const maps = CrossToolData.getMaps();
 */
const CrossToolData = {
  /**
   * 获取装备设计器中的所有装备
   * @param {string|null} slotFilter - 按slot筛选（weapon/armor/accessory）
   */
  getEquipments(slotFilter = null) {
    const data = StorageHelper.getJSON('equipDesigner_equipments', []);
    if (slotFilter) return data.filter(e => e.slot === slotFilter);
    return data;
  },

  /**
   * 获取地图设计器中的所有地图
   */
  getMaps() {
    const mapList = StorageHelper.getJSON('mapDesigner_mapList', []);
    return mapList.map(m => {
      const data = StorageHelper.getJSON('mapDesigner_' + m.key);
      return data ? { ...m, data } : m;
    });
  },

  /**
   * 获取天赋树设计器中的自定义天赋树
   */
  getTalentTrees() {
    const keys = StorageHelper.getKeys('talent_tree_custom_');
    return keys.map(k => {
      const data = StorageHelper.getJSON('talent_tree_custom_' + k);
      return data ? { key: k, ...data } : null;
    }).filter(Boolean);
  },

  /**
   * 获取指定职业在指定等级的完整战斗属性
   * （含装备加成，如果装备设计器有该tier的装备数据）
   */
  getFullStats(classId, level, advancement = null, tier = null) {
    const baseStats = GameFormulas.calcStats(classId, level, advancement);
    if (!baseStats || !tier) return baseStats;

    // 查找匹配tier的装备
    const equipments = this.getEquipments();
    const weaponType = WEAPON_TYPES[Object.keys(WEAPON_TYPES).find(
      wt => WEAPON_TYPES[wt].classes.includes(classId)
    )];

    const matchingWeapons = equipments.filter(e =>
      e.slot === 'weapon' && e.tier === tier
    );
    const matchingArmors = equipments.filter(e =>
      e.slot === 'armor' && e.tier === tier
    );

    // 取第一个匹配的装备（如果有）
    if (matchingWeapons.length > 0) {
      const w = matchingWeapons[0];
      if (w.stats) {
        for (const [k, v] of Object.entries(w.stats)) {
          if (baseStats[k] !== undefined) baseStats[k] += v;
        }
      }
    }
    if (matchingArmors.length > 0) {
      const a = matchingArmors[0];
      if (a.stats) {
        for (const [k, v] of Object.entries(a.stats)) {
          if (baseStats[k] !== undefined) baseStats[k] += v;
        }
      }
    }

    return baseStats;
  },
};

// ============================================================
// 国际化 (i18n) — 语言切换系统
// ============================================================

const I18N = {
  _lang: localStorage.getItem('designTools_lang') || 'zh',

  // 通用UI词汇（各工具共享）
  _dict: {
    zh: {
      // 通用操作
      save: '保存', delete: '删除', export: '导出', import: '导入',
      create: '新建', copy: '复制', cancel: '取消', confirm: '确认',
      close: '关闭', search: '搜索', reset: '重置', apply: '应用',
      undo: '撤销', redo: '重做', help: '帮助', ok: '确定',
      // 通用标签
      name: '名称', id: 'ID', type: '类型', description: '描述',
      level: '等级', cost: '花费', tags: '标签', notes: '备注',
      // 天赋树编辑器
      tt_title: '天赋树编辑器',
      tt_select: '选择', tt_connect: '连线', tt_del_edge: '删边',
      tt_auto_layout: '自动布局', tt_fit_view: '适应视图',
      tt_validate: '校验', tt_path: '路径',
      tt_basic_info: '基础信息', tt_description: '描述信息',
      tt_constraints: '约束条件', tt_effect: '效果',
      tt_design_notes: '设计备注',
      tt_exclusive_group: '互斥组',
      tt_required_nodes: '前置节点ID（逗号分隔）',
      tt_tags: '标签（逗号分隔）',
      tt_duplicate: '复制节点', tt_delete_node: '删除节点',
      tt_export_json: '导出JSON', tt_import_json: '导入JSON',
      tt_import_file_hint: '点击选择本地JSON文件', tt_import_or: '或者',
      tt_import_text_placeholder: '在此粘贴JSON内容...',
      tt_cancel: '取消', tt_confirm_import: '确认导入',
      tt_export_png: '导出PNG', tt_export_mermaid: 'Mermaid',
      tt_click_to_edit: '点击节点进行编辑',
      tt_dblclick_create: '双击画布创建节点',
      tt_press_h: '按 H 查看帮助',
      tt_search_placeholder: '按名称或标签搜索节点...',
      tt_new_tree: '+ 新建天赋页',
      tt_custom_trees: '── 自定义天赋页 ──',
      // 天赋树 - 文件系统
      tt_fs_connected: '已连接', tt_fs_disconnected: '未连接', tt_fs_saved: '待恢复',
      tt_fs_pick_dir: '📂 选择目录', tt_fs_rebind: '重新绑定', tt_fs_restore: '恢复连接', tt_fs_unsupported: '浏览器不支持',
      // 天赋树 - 校验
      tt_val_title: 'DAG 校验结果', tt_val_ok: '确定',
      tt_val_all_pass: '所有检查通过！',
      tt_val_dup_id: '重复ID', tt_val_no_dup: '无重复ID',
      tt_val_cycle: '检测到环', tt_val_no_cycle: '无环（有效DAG）',
      tt_val_orphan: '孤立节点', tt_val_no_orphan: '无孤立节点',
      tt_val_missing_src: '边引用缺失源节点', tt_val_missing_tgt: '边引用缺失目标节点',
      tt_val_missing_req: '前置节点引用缺失', tt_val_requires_ok: '所有前置节点引用有效',
      tt_node_name_placeholder: '节点名称',
      tt_node_id_placeholder: '唯一节点ID',
      tt_node_desc_placeholder: '描述节点效果...',
      tt_node_notes_placeholder: '内部设计备注...',
      tt_node_exclusive_placeholder: '例: adv_choice',
      tt_node_requires_placeholder: '例: node_a, node_b',
      tt_node_tags_placeholder: '例: fire, aoe, melee',
      // 天赋树节点类型
      nt_active_skill: '主动技能', nt_passive: '被动', nt_trait: '特质',
      nt_skill_upgrade: '技能升级', nt_advancement: '转职',
      nt_gauge_core: '量谱核心', nt_gauge_extend: '量谱扩展',
      nt_stat_minor: '小属性',
      // 帮助面板
      help_title: '键盘与鼠标操作',
      help_dblclick: '双击', help_dblclick_desc: '创建新节点',
      help_click_node: '点击节点', help_click_node_desc: '选中并在侧栏编辑',
      help_drag_node: '拖拽节点', help_drag_node_desc: '移动节点位置',
      help_drag_canvas: '拖拽画布', help_drag_canvas_desc: '平移视图',
      help_scroll: '滚轮', help_scroll_desc: '缩放',
      help_del: 'Delete / Backspace', help_del_desc: '删除选中节点',
      help_node_types: '节点类型',
      help_connect_mode: '连线模式',
      help_connect_desc: '连线模式下，点击源节点再点击目标节点创建有向边（前置关系）。删边模式下，点击边将其删除。',
      // 装备设计器
      eq_title: '装备设计器',
      eq_new: '+ 新建装备', eq_slot: '槽位', eq_weapon_type: '武器类型',
      eq_rarity: '稀有度', eq_tier: '阶段',
      eq_stats: '属性', eq_add_stat: '+ 添加属性',
      eq_special_effect: '特殊效果', eq_enable_effect: '启用特效',
      eq_effect_type: '效果类型', eq_effect_value: '数值',
      eq_effect_condition: '触发条件',
      eq_equip_tags: '装备限制标签', eq_add_tag: '添加',
      eq_preview: '装备预览', eq_tier_ref: '阶段数值参考',
      eq_json_preview: 'JSON预览', eq_copy_json: '复制',
      eq_batch_export: '批量导出全部', eq_search_placeholder: '搜索装备...',
      eq_all_slots: '全部槽位', eq_all_rarity: '全部稀有度',
      eq_all_tiers: '全部阶段',
      eq_slot_weapon: '武器', eq_slot_armor: '护甲', eq_slot_accessory: '饰品',
      eq_no_selection: '← 从左侧选择或新建装备',
      eq_copy_equip: '复制装备', eq_delete_equip: '删除',
      // 地图设计器
      map_title: '地图设计器',
      map_width: '宽', map_height: '高', map_apply_size: '应用尺寸',
      map_layer_terrain: '地形', map_layer_special: '特殊地形',
      map_layer_building: '建筑', map_layer_spawn: '出生点',
      map_layer_build_zone: '建造区域',
      map_export: '导出 JSON', map_import: '导入 JSON', map_clear: '清空地图',
      map_maps: '地图列表', map_new_map: '新建地图',
      map_info: '地图信息', map_stats: '统计信息',
      map_wave_config: 'Wave配置',
      map_management: '地图管理',
      map_palette: '调色板',
      map_basic_info: '基础信息',
      map_map_id: '地图 ID',
      map_map_name: '地图名称',
      map_json_preview: 'JSON 预览',
      map_ready: '就绪',
      map_map_size: '地图尺寸',
      map_passable_rate: '可通行率',
      map_special_terrain_count: '特殊地形',
      map_building_count: '建筑',
      map_spawn_count: '出生点',
      map_build_zone_status: '建造区域',
      map_set: '已设置', map_not_set: '未设置',
      map_cells: '格',
      map_no_maps: '暂无地图',
      map_unknown: '未知', map_unnamed: '未命名',
      map_current: '当前',
      map_switch: '切换', map_duplicate: '复制',
      map_new_map_name: '新地图',
      map_created: '已创建新地图',
      map_switched: '已切换到地图',
      map_duplicated: '已复制地图',
      map_deleted: '已删除地图',
      map_cleared: '地图已清空',
      map_exported: '已导出',
      map_imported: '已导入地图',
      map_import_failed: '导入失败',
      map_invalid_json: '无效的地图JSON: 缺少terrain数组',
      map_imported_name: '导入地图',
      map_resize_done: '地图尺寸已调整为',
      map_confirm_clear: '确定要清空当前地图的所有数据吗？',
      map_confirm_delete: '确定要删除地图 "{name}" 吗？',
      map_copy_suffix: '副本',
      // 地图设计器 - 地形名
      map_terrain_plain: '平地', map_terrain_forest: '树林',
      map_terrain_mountain: '山地', map_terrain_peak: '山峰',
      map_terrain_wall: '墙壁', map_terrain_shallow_water: '浅水',
      map_terrain_deep_water: '深水', map_terrain_lava: '熔岩',
      map_terrain_swamp: '毒沼',
      // 地图设计器 - 地形效果
      map_effect_none: '无', map_effect_evade: '+闪避',
      map_effect_def_mdef: '+防御,+魔防', map_effect_impassable: '-',
      map_effect_wet: '潮湿', map_effect_burn: '燃烧', map_effect_poison: '中毒',
      map_move_impassable: '不可',
      map_move_label: '移动',
      map_blocks_los: '阻挡攻击线: 是',
      // 地图设计器 - 特殊地形名
      map_st_healing_ground: '治愈之地', map_st_buff_zone: '增益区域',
      map_st_debuff_zone: '减益区域', map_st_trap: '陷阱',
      map_st_teleporter: '传送阵',
      map_teleporter_hint: '点击两格设置传送对',
      map_teleporter_pair_hint: '请点击第二个格子完成传送阵配对',
      map_teleporter_paired: '传送阵配对',
      // 地图设计器 - 建筑名
      map_bld_watchtower: '哨塔', map_bld_fortress: '要塞',
      map_bld_barricade: '拒马', map_bld_magic_tower: '魔法塔',
      // 地图设计器 - 调色板
      map_eraser: '橡皮擦',
      map_erase_special: '删除特殊地形',
      map_erase_building: '删除建筑',
      map_spawn_point: '出生点',
      map_spawn_desc: '玩家出生位置',
      map_spawn_action: '点击放置/移除',
      map_spawn_info: '左键点击格子添加出生点，右键或再次左键移除已有出生点。',
      map_buildzone_item: '建造区域',
      map_buildzone_rect: '矩形区域',
      map_buildzone_action: '拖拽设置范围',
      map_clear_buildzone: '清除建造区域',
      map_buildzone_info: '在地图上拖拽绘制矩形建造区域。建造区域定义玩家可在准备阶段放置建筑的范围。',
      map_buildzone_label: '建造区域',
      // 地图设计器 - tooltip
      map_tooltip_coord: '坐标',
      map_tooltip_terrain: '地形',
      map_tooltip_move: '移动',
      map_tooltip_move_impassable: '不可通行',
      map_tooltip_effect: '效果',
      map_tooltip_special: '特殊地形',
      map_tooltip_building: '建筑',
      map_tooltip_spawn: '玩家出生点',
      map_tooltip_in_buildzone: '建造区域内',
      // 导航首页
      idx_title: 'Ship of Theseus',
      idx_subtitle: '战棋RPG 设计工具套件',
      idx_talent_tree: '天赋树编辑器',
      idx_talent_desc: '可视化设计天赋树拓扑结构、节点属性和连接关系。支持DAG验证、路径成本分析、互斥可视化。',
      idx_equipment: '装备设计器',
      idx_equip_desc: '设计武器、护甲、饰品的属性数值和特殊效果。内含阶段数值参考和装备预览卡片。',
      idx_map: '地图设计器',
      idx_map_desc: '像素级地图编辑器，支持9种基础地形、特殊地形、建筑、出生点和建造区域的三层绘制。',
      idx_damage: '伤害模拟器',
      idx_damage_desc: '基于完整战斗公式的伤害计算器，支持职业预设、天赋层加成、蒙特卡洛模拟和节点对比。',
      idx_data_status: '本地数据状态',
      idx_custom_trees: '自定义天赋树',
      idx_equipment_label: '装备 (武器/护甲/饰品)',
      idx_maps: '地图',
      idx_storage: 'localStorage 占用',
      idx_count_unit: '个',
      idx_shared_component: '共享组件',
      idx_design_docs: '设计文档',
      idx_project_tagline: '战棋RPG + Roguelite + 城镇建设',
      idx_loading: '加载中...',
      // 伤害模拟器
      dmg_title: '伤害模拟器',
      dmg_attacker: '攻击方',
      dmg_defender: '防御方',
      dmg_results: '计算结果',
      dmg_preset: '职业预设',
      dmg_custom: '自定义',
      dmg_skill_power: '技能倍率',
      dmg_element_type: '属性类型',
      dmg_attack_type: '攻击方式',
      dmg_terrain_mod: '地形修正',
      dmg_final_mod: '最终增减',
      dmg_calculate: '计算',
      dmg_monte_carlo: '蒙特卡洛模拟',
      dmg_simulate: '模拟 1000 次',
      dmg_avg_damage: '平均伤害',
      dmg_hit_rate: '实际命中率',
      dmg_crit_rate: '实际暴击率',
      dmg_max: '最大',
      dmg_min: '最小',
      dmg_talent_layer: '天赋层加成',
      dmg_compare: '节点对比',
      // 稀有度
      rarity_common: '普通', rarity_uncommon: '精良',
      rarity_rare: '稀有', rarity_epic: '史诗', rarity_legendary: '传说',
      // 语言
      lang_switch: '语言',
    },

    en: {
      save: 'Save', delete: 'Delete', export: 'Export', import: 'Import',
      create: 'Create', copy: 'Copy', cancel: 'Cancel', confirm: 'Confirm',
      close: 'Close', search: 'Search', reset: 'Reset', apply: 'Apply',
      undo: 'Undo', redo: 'Redo', help: 'Help', ok: 'OK',
      name: 'Name', id: 'ID', type: 'Type', description: 'Description',
      level: 'Level', cost: 'Cost', tags: 'Tags', notes: 'Notes',
      tt_title: 'Talent Tree Editor',
      tt_select: 'Select', tt_connect: 'Connect', tt_del_edge: 'Del Edge',
      tt_auto_layout: 'Auto Layout', tt_fit_view: 'Fit View',
      tt_validate: 'Validate', tt_path: 'Path',
      tt_basic_info: 'Basic Info', tt_description: 'Description',
      tt_constraints: 'Constraints', tt_effect: 'Effect',
      tt_design_notes: 'Design Notes',
      tt_exclusive_group: 'Exclusive Group (mutual exclusion)',
      tt_required_nodes: 'Required Node IDs (comma-separated)',
      tt_tags: 'Tags (comma-separated)',
      tt_duplicate: 'Duplicate', tt_delete_node: 'Delete Node',
      tt_export_json: 'Export JSON', tt_import_json: 'Import JSON',
      tt_import_file_hint: 'Click to select local JSON file', tt_import_or: 'OR',
      tt_import_text_placeholder: 'Paste JSON content here...',
      tt_cancel: 'Cancel', tt_confirm_import: 'Confirm Import',
      tt_export_png: 'Export PNG', tt_export_mermaid: 'Mermaid',
      tt_click_to_edit: 'Click a node to edit',
      tt_dblclick_create: 'Double-click canvas to create node',
      tt_press_h: 'Press H for help',
      tt_search_placeholder: 'Search nodes by name or tags...',
      tt_new_tree: '+ New Tree',
      tt_custom_trees: '── Custom Trees ──',
      // Talent tree - File system
      tt_fs_connected: 'Connected', tt_fs_disconnected: 'Not Connected', tt_fs_saved: 'Saved',
      tt_fs_pick_dir: '📂 Select Directory', tt_fs_rebind: 'Rebind', tt_fs_restore: 'Reconnect', tt_fs_unsupported: 'Browser Unsupported',
      // Talent tree - Validation
      tt_val_title: 'DAG Validation Results', tt_val_ok: 'OK',
      tt_val_all_pass: 'All checks passed!',
      tt_val_dup_id: 'Duplicate ID', tt_val_no_dup: 'No duplicate IDs',
      tt_val_cycle: 'Cycle detected', tt_val_no_cycle: 'No cycles (valid DAG)',
      tt_val_orphan: 'Orphan node', tt_val_no_orphan: 'No orphan nodes',
      tt_val_missing_src: 'Edge references missing source', tt_val_missing_tgt: 'Edge references missing target',
      tt_val_missing_req: 'Requires references missing node', tt_val_requires_ok: 'All requires references valid',
      tt_node_name_placeholder: 'Node name',
      tt_node_id_placeholder: 'unique_node_id',
      tt_node_desc_placeholder: 'Describe the node effect...',
      tt_node_notes_placeholder: 'Internal design notes...',
      tt_node_exclusive_placeholder: 'e.g. adv_choice',
      tt_node_requires_placeholder: 'e.g. node_a, node_b',
      tt_node_tags_placeholder: 'e.g. fire, aoe, melee',
      nt_active_skill: 'Active Skill', nt_passive: 'Passive', nt_trait: 'Trait',
      nt_skill_upgrade: 'Skill Upgrade', nt_advancement: 'Advancement',
      nt_gauge_core: 'Gauge Core', nt_gauge_extend: 'Gauge Extend',
      nt_stat_minor: 'Stat (minor)',
      help_title: 'Keyboard & Mouse',
      help_dblclick: 'Double-click', help_dblclick_desc: 'Create new node',
      help_click_node: 'Click node', help_click_node_desc: 'Select & edit in sidebar',
      help_drag_node: 'Drag node', help_drag_node_desc: 'Move node position',
      help_drag_canvas: 'Drag canvas', help_drag_canvas_desc: 'Pan view',
      help_scroll: 'Scroll', help_scroll_desc: 'Zoom in/out',
      help_del: 'Delete / Backspace', help_del_desc: 'Delete selected node',
      help_node_types: 'Node Types',
      help_connect_mode: 'Connect Mode',
      help_connect_desc: 'In Connect mode, click a source node then click a target node to create a directed edge. In Delete Edge mode, click on any edge to remove it.',
      eq_title: 'Equipment Designer',
      eq_new: '+ New Equipment', eq_slot: 'Slot', eq_weapon_type: 'Weapon Type',
      eq_rarity: 'Rarity', eq_tier: 'Tier',
      eq_stats: 'Stats', eq_add_stat: '+ Add Stat',
      eq_special_effect: 'Special Effect', eq_enable_effect: 'Enable Effect',
      eq_effect_type: 'Effect Type', eq_effect_value: 'Value',
      eq_effect_condition: 'Condition',
      eq_equip_tags: 'Equip Tags', eq_add_tag: 'Add',
      eq_preview: 'Equipment Preview', eq_tier_ref: 'Tier Reference',
      eq_json_preview: 'JSON Preview', eq_copy_json: 'Copy',
      eq_batch_export: 'Export All', eq_search_placeholder: 'Search equipment...',
      eq_all_slots: 'All Slots', eq_all_rarity: 'All Rarity',
      eq_all_tiers: 'All Tiers',
      eq_slot_weapon: 'Weapon', eq_slot_armor: 'Armor', eq_slot_accessory: 'Accessory',
      eq_no_selection: '← Select or create equipment from left panel',
      eq_copy_equip: 'Copy Equipment', eq_delete_equip: 'Delete',
      map_title: 'Map Designer',
      map_width: 'Width', map_height: 'Height', map_apply_size: 'Apply Size',
      map_layer_terrain: 'Terrain', map_layer_special: 'Special Terrain',
      map_layer_building: 'Building', map_layer_spawn: 'Spawn',
      map_layer_build_zone: 'Build Zone',
      map_export: 'Export JSON', map_import: 'Import JSON', map_clear: 'Clear Map',
      map_maps: 'Map List', map_new_map: 'New Map',
      map_info: 'Map Info', map_stats: 'Statistics',
      map_wave_config: 'Wave Config',
      map_management: 'Map Management',
      map_palette: 'Palette',
      map_basic_info: 'Basic Info',
      map_map_id: 'Map ID',
      map_map_name: 'Map Name',
      map_json_preview: 'JSON Preview',
      map_ready: 'Ready',
      map_map_size: 'Map Size',
      map_passable_rate: 'Passable Rate',
      map_special_terrain_count: 'Special Terrain',
      map_building_count: 'Buildings',
      map_spawn_count: 'Spawns',
      map_build_zone_status: 'Build Zone',
      map_set: 'Set', map_not_set: 'Not Set',
      map_cells: 'cells',
      map_no_maps: 'No maps yet',
      map_unknown: 'Unknown', map_unnamed: 'Unnamed',
      map_current: 'Current',
      map_switch: 'Switch', map_duplicate: 'Duplicate',
      map_new_map_name: 'New Map',
      map_created: 'Created new map',
      map_switched: 'Switched to map',
      map_duplicated: 'Map duplicated',
      map_deleted: 'Map deleted',
      map_cleared: 'Map cleared',
      map_exported: 'Exported',
      map_imported: 'Imported map',
      map_import_failed: 'Import failed',
      map_invalid_json: 'Invalid map JSON: missing terrain array',
      map_imported_name: 'Imported Map',
      map_resize_done: 'Map resized to',
      map_confirm_clear: 'Are you sure you want to clear all data of the current map?',
      map_confirm_delete: 'Are you sure you want to delete map "{name}"?',
      map_copy_suffix: 'Copy',
      // Map Designer - terrain names
      map_terrain_plain: 'Plain', map_terrain_forest: 'Forest',
      map_terrain_mountain: 'Mountain', map_terrain_peak: 'Peak',
      map_terrain_wall: 'Wall', map_terrain_shallow_water: 'Shallow Water',
      map_terrain_deep_water: 'Deep Water', map_terrain_lava: 'Lava',
      map_terrain_swamp: 'Swamp',
      // Map Designer - terrain effects
      map_effect_none: 'None', map_effect_evade: '+Evasion',
      map_effect_def_mdef: '+DEF,+MDEF', map_effect_impassable: '-',
      map_effect_wet: 'Wet', map_effect_burn: 'Burn', map_effect_poison: 'Poison',
      map_move_impassable: 'N/A',
      map_move_label: 'Move',
      map_blocks_los: 'Blocks LOS: Yes',
      // Map Designer - special terrain names
      map_st_healing_ground: 'Healing Ground', map_st_buff_zone: 'Buff Zone',
      map_st_debuff_zone: 'Debuff Zone', map_st_trap: 'Trap',
      map_st_teleporter: 'Teleporter',
      map_teleporter_hint: 'Click two cells to set teleporter pair',
      map_teleporter_pair_hint: 'Click the second cell to complete teleporter pair',
      map_teleporter_paired: 'Teleporter paired',
      // Map Designer - building names
      map_bld_watchtower: 'Watchtower', map_bld_fortress: 'Fortress',
      map_bld_barricade: 'Barricade', map_bld_magic_tower: 'Magic Tower',
      // Map Designer - palette
      map_eraser: 'Eraser',
      map_erase_special: 'Erase special terrain',
      map_erase_building: 'Erase building',
      map_spawn_point: 'Spawn Point',
      map_spawn_desc: 'Player spawn position',
      map_spawn_action: 'Click to place/remove',
      map_spawn_info: 'Left-click a cell to add a spawn point, right-click or click again to remove.',
      map_buildzone_item: 'Build Zone',
      map_buildzone_rect: 'Rectangle',
      map_buildzone_action: 'Drag to set area',
      map_clear_buildzone: 'Clear Build Zone',
      map_buildzone_info: 'Drag on the map to draw a rectangular build zone. The build zone defines where players can place buildings during the preparation phase.',
      map_buildzone_label: 'Build Zone',
      // Map Designer - tooltip
      map_tooltip_coord: 'Coord',
      map_tooltip_terrain: 'Terrain',
      map_tooltip_move: 'Move',
      map_tooltip_move_impassable: 'Impassable',
      map_tooltip_effect: 'Effect',
      map_tooltip_special: 'Special',
      map_tooltip_building: 'Building',
      map_tooltip_spawn: 'Player Spawn',
      map_tooltip_in_buildzone: 'In Build Zone',
      // Index page
      idx_title: 'Ship of Theseus',
      idx_subtitle: 'SRPG Design Tool Suite',
      idx_talent_tree: 'Talent Tree Editor',
      idx_talent_desc: 'Visual talent tree topology editor with node properties and connections. Supports DAG validation, path cost analysis, mutual exclusion visualization.',
      idx_equipment: 'Equipment Designer',
      idx_equip_desc: 'Design weapon, armor and accessory stats and special effects. Includes tier reference and equipment preview cards.',
      idx_map: 'Map Designer',
      idx_map_desc: 'Pixel-level map editor supporting 9 terrain types, special terrain, buildings, spawn points and build zones in three layers.',
      idx_damage: 'Damage Simulator',
      idx_damage_desc: 'Battle formula-based damage calculator with class presets, talent bonuses, Monte Carlo simulation and node comparison.',
      idx_data_status: 'Local Data Status',
      idx_custom_trees: 'Custom Talent Trees',
      idx_equipment_label: 'Equipment (Weapon/Armor/Accessory)',
      idx_maps: 'Maps',
      idx_storage: 'localStorage Usage',
      idx_count_unit: '',
      idx_shared_component: 'Shared Component',
      idx_design_docs: 'Design Docs',
      idx_project_tagline: 'SRPG + Roguelite + Town Building',
      idx_loading: 'Loading...',
      // Damage Simulator
      dmg_title: 'Damage Simulator',
      dmg_attacker: 'Attacker',
      dmg_defender: 'Defender',
      dmg_results: 'Results',
      dmg_preset: 'Class Preset',
      dmg_custom: 'Custom',
      dmg_skill_power: 'Skill Power',
      dmg_element_type: 'Element Type',
      dmg_attack_type: 'Attack Type',
      dmg_terrain_mod: 'Terrain Mod',
      dmg_final_mod: 'Final Mod',
      dmg_calculate: 'Calculate',
      dmg_monte_carlo: 'Monte Carlo Simulation',
      dmg_simulate: 'Simulate 1000 Runs',
      dmg_avg_damage: 'Avg Damage',
      dmg_hit_rate: 'Actual Hit Rate',
      dmg_crit_rate: 'Actual Crit Rate',
      dmg_max: 'Max',
      dmg_min: 'Min',
      dmg_talent_layer: 'Talent Layer Bonus',
      dmg_compare: 'Node Comparison',
      rarity_common: 'Common', rarity_uncommon: 'Uncommon',
      rarity_rare: 'Rare', rarity_epic: 'Epic', rarity_legendary: 'Legendary',
      lang_switch: 'Language',
    },
  },

  /** 获取当前语言 */
  get lang() { return this._lang; },

  /** 切换语言并持久化 */
  setLang(lang) {
    this._lang = lang;
    localStorage.setItem('designTools_lang', lang);
  },

  /** 取翻译文本，找不到返回key本身 */
  t(key) {
    const dict = this._dict[this._lang] || this._dict.zh;
    return dict[key] !== undefined ? dict[key] : key;
  },

  /** 创建语言切换器DOM元素 */
  createLangSwitcher() {
    const container = document.createElement('div');
    container.style.cssText = 'display:inline-flex;align-items:center;gap:4px;';

    const select = document.createElement('select');
    select.style.cssText = 'padding:3px 6px;background:#1a1a2e;color:#a0a0a0;border:1px solid #1a5276;border-radius:3px;font-size:11px;cursor:pointer;';
    select.innerHTML = '<option value="zh">中文</option><option value="en">EN</option>';
    select.value = this._lang;
    select.onchange = () => {
      this.setLang(select.value);
      location.reload(); // 刷新页面应用新语言
    };

    const label = document.createElement('span');
    label.textContent = '🌐';
    label.style.cssText = 'font-size:13px;cursor:default;';

    container.appendChild(label);
    container.appendChild(select);
    return container;
  },
};

// ============================================================
// 导出标记（供其他工具检测shared.js是否已加载）
// ============================================================
window.__SHARED_LOADED__ = true;

console.log(`[Shared] Ship of Theseus Design Tools v${SHARED_VERSION} loaded. Lang: ${I18N.lang}`);
