import { useState, useMemo, useCallback } from "react";

// --- DATA DEFINITIONS ---
const CLASSES = {
  warrior: { name: "战士", hp: 120, attack: 15, magic: 5, pDef: 12, mDef: 6, speed: 8, move: 3, hit: 80, evade: 5, crit: 5, critEvade: 5, block: 15, res: 5 },
  archer:  { name: "弓手", hp: 80, attack: 18, magic: 5, pDef: 6, mDef: 5, speed: 10, move: 3, hit: 90, evade: 10, crit: 15, critEvade: 5, block: 0, res: 5 },
  mage:    { name: "法师", hp: 70, attack: 8, magic: 20, pDef: 4, mDef: 10, speed: 7, move: 2, hit: 85, evade: 5, crit: 5, critEvade: 5, block: 0, res: 10 },
  rogue:   { name: "盗贼", hp: 85, attack: 14, magic: 5, pDef: 5, mDef: 6, speed: 14, move: 5, hit: 85, evade: 20, crit: 10, critEvade: 5, block: 5, res: 5 },
};

const ENEMIES = {
  grunt:   { name: "普通小兵", hp: 60, pDef: 6, mDef: 4, evade: 5, critEvade: 3, block: 0, res: 0 },
  tank:    { name: "重甲兵(物防高)", hp: 80, pDef: 14, mDef: 4, evade: 0, critEvade: 5, block: 10, res: 5 },
  mRes:    { name: "法抗兵(魔防高)", hp: 70, pDef: 5, mDef: 14, evade: 5, critEvade: 3, block: 0, res: 10 },
  elite:   { name: "精英", hp: 150, pDef: 10, mDef: 8, evade: 10, critEvade: 8, block: 5, res: 15 },
  boss:    { name: "Boss", hp: 400, pDef: 14, mDef: 12, evade: 8, critEvade: 10, block: 10, res: 20 },
};

const WEAPONS = {
  sword:    { name: "铁剑", power: 1.0, hit: 5, crit: 0 },
  axe:      { name: "战斧", power: 1.2, hit: -5, crit: 5 },
  bow:      { name: "短弓", power: 0.9, hit: 10, crit: 5 },
  longbow:  { name: "长弓", power: 1.0, hit: 5, crit: 10 },
  staff:    { name: "法杖", power: 1.0, hit: 5, crit: 0, magic: true },
  dagger:   { name: "匕首", power: 0.8, hit: 10, crit: 15 },
};

const ARMORS = {
  none:   { name: "无护甲", resistance: 0.0 },
  light:  { name: "轻甲", resistance: 0.8 },
  medium: { name: "中甲", resistance: 1.0 },
  heavy:  { name: "重甲", resistance: 1.2 },
};

const SKILLS = {
  normal: { name: "普通攻击", power: 100, hitBonus: 0, critBonus: 0 },
  heavy:  { name: "重击(150%)", power: 150, hitBonus: -5, critBonus: 0 },
  quick:  { name: "快速斩(80%)", power: 80, hitBonus: 5, critBonus: 0 },
  snipe:  { name: "狙击(120%)", power: 120, hitBonus: 10, critBonus: 5 },
  crit_s: { name: "暴击技(100%+暴击30)", power: 100, hitBonus: 0, critBonus: 30 },
  nuke:   { name: "大招(200%)", power: 200, hitBonus: -10, critBonus: 0 },
};

const BUFFS = [
  { id: "none", name: "无Buff", atkMul: 1.0, finalMul: 1.0, hitBonus: 0, critBonus: 0, critDmgBonus: 0 },
  { id: "atk_up", name: "攻击+30%", atkMul: 1.3, finalMul: 1.0, hitBonus: 0, critBonus: 0, critDmgBonus: 0 },
  { id: "final_up", name: "最终伤害+20%", atkMul: 1.0, finalMul: 1.2, hitBonus: 0, critBonus: 0, critDmgBonus: 0 },
  { id: "crit_dmg_up", name: "暴击伤害+0.5", atkMul: 1.0, finalMul: 1.0, hitBonus: 0, critBonus: 0, critDmgBonus: 0.5 },
  { id: "all_small", name: "全属性小幅(攻+15%/终伤+10%/命+10/暴+10)", atkMul: 1.15, finalMul: 1.1, hitBonus: 10, critBonus: 10, critDmgBonus: 0 },
  { id: "stacked", name: "满Buff(攻+40%/终伤+30%/暴伤+0.5)", atkMul: 1.4, finalMul: 1.3, hitBonus: 10, critBonus: 15, critDmgBonus: 0.5 },
];

// --- CALCULATION ENGINE ---
function simulate(attacker, weapon, armor, skill, buff, defender, terrainDef, specialTerrainMul, level, trials = 10000) {
  const lvlBonus = level - 1;
  const atk = weapon.magic
    ? (attacker.magic + lvlBonus * 2.5) * (buff.atkMul)
    : (attacker.attack + lvlBonus * 2.0) * (buff.atkMul);
  const weaponPow = weapon.power;
  const def = weapon.magic
    ? defender.mDef + terrainDef
    : defender.pDef + terrainDef;
  const armorRes = armor.resistance;
  const skillPow = skill.power / 100;
  const baseDmg = Math.max(0, atk * weaponPow - def * armorRes);
  const hitRate = Math.min(100, Math.max(20,
    attacker.hit + weapon.hit + skill.hitBonus + buff.hitBonus - defender.evade
  )) / 100;
  const blockRate = defender.block / 100;
  const rawCrit = Math.min(50, Math.max(0,
    attacker.crit + weapon.crit + skill.critBonus + buff.critBonus - defender.critEvade
  )) / 100;
  const critMul = 1.5 + buff.critDmgBonus;
  const finalMul = buff.finalMul * specialTerrainMul;

  let totalDmg = 0, hits = 0, crits = 0, blocks = 0, misses = 0;
  for (let i = 0; i < trials; i++) {
    if (Math.random() > hitRate) { misses++; continue; }
    hits++;
    let blocked = false, isCrit = false;
    if (Math.random() < blockRate) { blocked = true; blocks++; }
    else if (Math.random() < rawCrit) { isCrit = true; crits++; }
    let dmg = baseDmg * skillPow * specialTerrainMul;
    if (isCrit) dmg *= critMul;
    if (blocked) dmg *= 0.3;
    dmg *= finalMul;
    totalDmg += Math.max(0, Math.round(dmg));
  }
  const avgDmg = hits > 0 ? totalDmg / hits : 0;
  const dps = totalDmg / trials;
  const hitsToKill = avgDmg > 0 ? Math.ceil(defender.hp / avgDmg) : Infinity;
  const expectedHitsToKill = dps > 0 ? Math.ceil(defender.hp / dps) : Infinity;

  return {
    baseDmg: Math.round(baseDmg),
    skillDmg: Math.round(baseDmg * skillPow),
    hitRate: Math.round(hitRate * 100),
    blockRate: Math.round(blockRate * 100),
    critRate: Math.round(rawCrit * 100),
    critMul,
    avgDmgOnHit: Math.round(avgDmg),
    expectedDmg: Math.round(dps),
    hitsToKill,
    expectedHitsToKill,
    enemyHp: defender.hp,
    missRate: Math.round((misses / trials) * 100),
    critPercent: Math.round((crits / trials) * 100),
    blockPercent: Math.round((blocks / trials) * 100),
  };
}

// --- UI COMPONENTS ---
function Select({ label, value, onChange, options, small }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
      <label style={{ fontSize: small ? 11 : 12, color: "#8a8f98", fontWeight: 500, letterSpacing: "0.02em" }}>{label}</label>
      <select value={value} onChange={e => onChange(e.target.value)} style={{
        padding: small ? "4px 6px" : "6px 8px", borderRadius: 6, border: "1px solid #2a2d35",
        background: "#13151a", color: "#e2e4e9", fontSize: small ? 12 : 13, outline: "none",
        cursor: "pointer"
      }}>
        {Object.entries(options).map(([k, v]) => <option key={k} value={k}>{typeof v === "string" ? v : v.name}</option>)}
      </select>
    </div>
  );
}

function Slider({ label, value, onChange, min, max, step = 1, unit = "" }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
        <label style={{ fontSize: 12, color: "#8a8f98", fontWeight: 500 }}>{label}</label>
        <span style={{ fontSize: 13, color: "#c9f06b", fontWeight: 600, fontFamily: "'JetBrains Mono', monospace" }}>{value}{unit}</span>
      </div>
      <input type="range" min={min} max={max} step={step} value={value} onChange={e => onChange(Number(e.target.value))}
        style={{ width: "100%", accentColor: "#c9f06b" }} />
    </div>
  );
}

function StatBar({ label, value, max, color = "#c9f06b", suffix = "" }) {
  const pct = Math.min(100, (value / max) * 100);
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 12 }}>
      <span style={{ width: 80, color: "#8a8f98", textAlign: "right", flexShrink: 0 }}>{label}</span>
      <div style={{ flex: 1, height: 14, background: "#1a1d24", borderRadius: 7, overflow: "hidden", position: "relative" }}>
        <div style={{ width: `${pct}%`, height: "100%", background: color, borderRadius: 7, transition: "width 0.3s ease" }} />
      </div>
      <span style={{ width: 55, fontFamily: "'JetBrains Mono', monospace", color: "#e2e4e9", fontWeight: 600, flexShrink: 0 }}>
        {typeof value === "number" ? (Number.isFinite(value) ? value : "∞") : value}{suffix}
      </span>
    </div>
  );
}

function ResultCard({ title, result, color }) {
  if (!result) return null;
  const killColor = result.expectedHitsToKill <= 1 ? "#4ade80" : result.expectedHitsToKill <= 2 ? "#c9f06b" : result.expectedHitsToKill <= 4 ? "#fbbf24" : "#f87171";
  return (
    <div style={{
      background: "#13151a", borderRadius: 10, padding: 14, border: `1px solid ${color}22`,
      display: "flex", flexDirection: "column", gap: 8
    }}>
      <div style={{ fontSize: 13, fontWeight: 600, color, marginBottom: 2 }}>{title}</div>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 4, fontSize: 12 }}>
        <span style={{ color: "#8a8f98" }}>基础伤害</span>
        <span style={{ color: "#e2e4e9", fontFamily: "'JetBrains Mono', monospace", textAlign: "right" }}>{result.baseDmg}</span>
        <span style={{ color: "#8a8f98" }}>技能后伤害</span>
        <span style={{ color: "#e2e4e9", fontFamily: "'JetBrains Mono', monospace", textAlign: "right" }}>{result.skillDmg}</span>
        <span style={{ color: "#8a8f98" }}>命中后均伤</span>
        <span style={{ color: "#c9f06b", fontFamily: "'JetBrains Mono', monospace", textAlign: "right", fontWeight: 700 }}>{result.avgDmgOnHit}</span>
        <span style={{ color: "#8a8f98" }}>期望伤害</span>
        <span style={{ color: "#c9f06b", fontFamily: "'JetBrains Mono', monospace", textAlign: "right", fontWeight: 700 }}>{result.expectedDmg}</span>
      </div>
      <div style={{ borderTop: "1px solid #2a2d35", paddingTop: 8, marginTop: 2 }}>
        <StatBar label="命中率" value={result.hitRate} max={100} color="#60a5fa" suffix="%" />
        <StatBar label="暴击率" value={result.critRate} max={50} color="#f472b6" suffix="%" />
        <StatBar label="被格挡率" value={result.blockRate} max={30} color="#fbbf24" suffix="%" />
        <StatBar label="暴击倍率" value={result.critMul} max={3} color="#a78bfa" suffix="x" />
      </div>
      <div style={{ borderTop: "1px solid #2a2d35", paddingTop: 8, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <span style={{ color: "#8a8f98", fontSize: 12 }}>
          击杀（{result.enemyHp}HP）
        </span>
        <span style={{ fontSize: 18, fontWeight: 800, color: killColor, fontFamily: "'JetBrains Mono', monospace" }}>
          {Number.isFinite(result.expectedHitsToKill) ? `${result.expectedHitsToKill}次攻击` : "无法击杀"}
        </span>
      </div>
    </div>
  );
}

// --- MAIN APP ---
export default function DamageSimulator() {
  const [cls, setCls] = useState("warrior");
  const [weapon, setWeapon] = useState("sword");
  const [armor, setArmor] = useState("medium");
  const [skill, setSkill] = useState("normal");
  const [buffId, setBuffId] = useState("none");
  const [level, setLevel] = useState(1);
  const [terrainDef, setTerrainDef] = useState(0);
  const [specialMul, setSpecialMul] = useState(100);

  const attacker = CLASSES[cls];
  const weaponData = WEAPONS[weapon];
  const armorData = ARMORS[armor];
  const skillData = SKILLS[skill];
  const buff = BUFFS.find(b => b.id === buffId);

  const results = useMemo(() => {
    const out = {};
    for (const [eid, enemy] of Object.entries(ENEMIES)) {
      out[eid] = simulate(attacker, weaponData, armorData, skillData, buff, enemy, terrainDef, specialMul / 100, level);
    }
    return out;
  }, [cls, weapon, armor, skill, buffId, level, terrainDef, specialMul]);

  const enemyColors = { grunt: "#4ade80", tank: "#60a5fa", mRes: "#a78bfa", elite: "#fbbf24", boss: "#f87171" };

  return (
    <div style={{
      minHeight: "100vh", background: "#0b0d11", color: "#e2e4e9",
      fontFamily: "'Inter', -apple-system, sans-serif", padding: "20px 16px"
    }}>
      <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600;800&family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet" />

      <div style={{ maxWidth: 900, margin: "0 auto" }}>
        <div style={{ marginBottom: 24 }}>
          <h1 style={{ fontSize: 22, fontWeight: 700, margin: 0, letterSpacing: "-0.02em" }}>
            ⚔️ 战棋Roguelite 伤害模拟器
          </h1>
          <p style={{ fontSize: 12, color: "#8a8f98", margin: "4px 0 0" }}>
            调整参数观察各乘区对伤害的影响 · 蒙特卡洛模拟10000次
          </p>
        </div>

        {/* Controls */}
        <div style={{
          display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
          gap: 12, background: "#13151a", borderRadius: 12, padding: 16, marginBottom: 16,
          border: "1px solid #1e2028"
        }}>
          <Select label="职业" value={cls} onChange={setCls} options={CLASSES} />
          <Select label="武器" value={weapon} onChange={setWeapon} options={WEAPONS} />
          <Select label="护甲(敌方)" value={armor} onChange={setArmor} options={ARMORS} />
          <Select label="技能" value={skill} onChange={setSkill} options={SKILLS} />
          <Select label="Buff组合" value={buffId} onChange={setBuffId}
            options={BUFFS.reduce((o, b) => ({ ...o, [b.id]: b.name }), {})} />
        </div>

        <div style={{
          display: "grid", gridTemplateColumns: "1fr 1fr 1fr",
          gap: 12, background: "#13151a", borderRadius: 12, padding: 16, marginBottom: 20,
          border: "1px solid #1e2028"
        }}>
          <Slider label="角色等级" value={level} onChange={setLevel} min={1} max={10} />
          <Slider label="地形防御加成" value={terrainDef} onChange={setTerrainDef} min={0} max={10} />
          <Slider label="特殊地形修正" value={specialMul} onChange={setSpecialMul} min={50} max={150} step={5} unit="%" />
        </div>

        {/* Attacker summary */}
        <div style={{
          background: "#13151a", borderRadius: 12, padding: 14, marginBottom: 16,
          border: "1px solid #1e2028", fontSize: 12
        }}>
          <div style={{ fontWeight: 600, color: "#c9f06b", marginBottom: 8 }}>
            {attacker.name} Lv.{level} · {weaponData.name} · {skillData.name}
            {buff.id !== "none" && ` · ${buff.name}`}
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(140px, 1fr))", gap: 4 }}>
            {[
              ["物攻", Math.round((attacker.attack + (level - 1) * 2.0) * buff.atkMul)],
              ["魔攻", Math.round((attacker.magic + (level - 1) * 2.5) * (weaponData.magic ? buff.atkMul : 1))],
              ["命中", attacker.hit + weaponData.hit + skillData.hitBonus + buff.hitBonus],
              ["暴击", Math.min(50, attacker.crit + weaponData.crit + skillData.critBonus + buff.critBonus)],
              ["暴击倍率", `${(1.5 + buff.critDmgBonus).toFixed(1)}x`],
              ["技能倍率", `${skillData.power}%`],
            ].map(([k, v]) => (
              <div key={k} style={{ display: "flex", justifyContent: "space-between", padding: "2px 0" }}>
                <span style={{ color: "#8a8f98" }}>{k}</span>
                <span style={{ fontFamily: "'JetBrains Mono', monospace", fontWeight: 600 }}>{v}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Results */}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: 12 }}>
          {Object.entries(ENEMIES).map(([eid, enemy]) => (
            <ResultCard key={eid} title={`vs ${enemy.name}`} result={results[eid]} color={enemyColors[eid]} />
          ))}
        </div>

        {/* Multiplier Analysis */}
        <div style={{
          background: "#13151a", borderRadius: 12, padding: 16, marginTop: 16,
          border: "1px solid #1e2028"
        }}>
          <div style={{ fontWeight: 600, fontSize: 14, marginBottom: 12, color: "#e2e4e9" }}>乘区贡献分析 (vs 普通小兵)</div>
          {(() => {
            const base = simulate(attacker, weaponData, armorData, SKILLS.normal, BUFFS[0], ENEMIES.grunt, 0, 1.0, level);
            const withSkill = simulate(attacker, weaponData, armorData, skillData, BUFFS[0], ENEMIES.grunt, 0, 1.0, level);
            const withBuff = simulate(attacker, weaponData, armorData, SKILLS.normal, buff, ENEMIES.grunt, 0, 1.0, level);
            const withTerrain = simulate(attacker, weaponData, armorData, SKILLS.normal, BUFFS[0], ENEMIES.grunt, terrainDef, specialMul / 100, level);
            const full = results.grunt;

            const baseDmg = base.expectedDmg || 1;
            const contributions = [
              { name: "基础(普攻/无Buff)", value: baseDmg, pct: 100 },
              { name: `技能(${skillData.name})`, value: withSkill.expectedDmg, pct: Math.round((withSkill.expectedDmg / baseDmg) * 100) },
              { name: `Buff(${buff.name})`, value: withBuff.expectedDmg, pct: Math.round((withBuff.expectedDmg / baseDmg) * 100) },
              { name: "地形修正", value: withTerrain.expectedDmg, pct: Math.round((withTerrain.expectedDmg / baseDmg) * 100) },
              { name: "全乘区叠加", value: full.expectedDmg, pct: Math.round((full.expectedDmg / baseDmg) * 100) },
            ];

            return (
              <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
                {contributions.map(c => (
                  <div key={c.name} style={{ display: "flex", alignItems: "center", gap: 8 }}>
                    <span style={{ width: 200, fontSize: 12, color: "#8a8f98", flexShrink: 0 }}>{c.name}</span>
                    <div style={{ flex: 1, height: 18, background: "#1a1d24", borderRadius: 4, overflow: "hidden", position: "relative" }}>
                      <div style={{
                        width: `${Math.min(100, (c.pct / (contributions[contributions.length - 1].pct || 100)) * 100)}%`,
                        height: "100%",
                        background: c.name === "全乘区叠加" ? "linear-gradient(90deg, #c9f06b, #4ade80)" : "#2a4a3a",
                        borderRadius: 4, transition: "width 0.3s"
                      }} />
                    </div>
                    <span style={{
                      width: 80, textAlign: "right", fontFamily: "'JetBrains Mono', monospace",
                      fontSize: 12, fontWeight: 600, color: c.pct > 150 ? "#4ade80" : "#e2e4e9"
                    }}>
                      {c.value} ({c.pct}%)
                    </span>
                  </div>
                ))}
              </div>
            );
          })()}
        </div>

        <div style={{ fontSize: 11, color: "#555", textAlign: "center", marginTop: 16 }}>
          数值为初始设计基线 · 调整参数观察各乘区权重 · 用于公式迭代验证
        </div>
      </div>
    </div>
  );
}
