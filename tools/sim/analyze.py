"""汇总 battle_sim.gd 的输出，写 summary.json。

用法：python tools/sim/analyze.py <输出目录>
读取 <输出目录>/battles.jsonl、actions.jsonl、events.jsonl 与 godot.log（battle_sim 的标准输出），
godot.log 里 [SIM] battle_begin / battle_end 之间的 SCRIPT ERROR、ERROR、WARNING 归到对应战斗。
"""
import collections
import json
import os
import re
import sys


def load_jsonl(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding='utf-8') as f:
        return [json.loads(line) for line in f if line.strip()]


def parse_log(path):
    """返回 {消息: {"count": n, "battles": [...]}}；只收 Godot 自身的报错与警告。"""
    out = {}
    if not os.path.exists(path):
        return out
    battle = '(战斗外)'
    pat = re.compile(r'^(SCRIPT ERROR|ERROR|WARNING|USER ERROR|USER WARNING): (.*)')
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.rstrip('\n')
            if line.startswith('[SIM] battle_begin '):
                battle = line.split(' ', 2)[2]
                continue
            if line.startswith('[SIM] battle_end '):
                battle = '(战斗外)'
                continue
            m = pat.match(line)
            if not m:
                continue
            # 去掉数字，让同一类消息归在一起
            msg = '%s: %s' % (m.group(1), re.sub(r'\d+', 'N', m.group(2))[:200])
            entry = out.setdefault(msg, {'count': 0, 'battles': []})
            entry['count'] += 1
            if battle not in entry['battles'] and len(entry['battles']) < 8:
                entry['battles'].append(battle)
    return out


def mean(xs):
    return round(sum(xs) / len(xs), 2) if xs else 0


def main(out_dir):
    battles = load_jsonl(os.path.join(out_dir, 'battles.jsonl'))
    actions = load_jsonl(os.path.join(out_dir, 'actions.jsonl'))
    events = load_jsonl(os.path.join(out_dir, 'events.jsonl'))

    by_config = collections.defaultdict(list)
    for b in battles:
        by_config[(b['lineup'], b['memory'])].append(b)
    configs = []
    for (lineup, memory), bs in sorted(by_config.items()):
        results = collections.Counter(b['result'] for b in bs)
        players = [u for b in bs for u in b['units'] if u['faction'] == 'player']
        configs.append({
            'lineup': lineup, 'memory': memory, 'battles': len(bs),
            'results': dict(results),
            'win_rate': round(results.get('victory', 0) / len(bs), 3),
            'rounds_avg': mean([b['rounds'] for b in bs]),
            'rounds_min': min(b['rounds'] for b in bs), 'rounds_max': max(b['rounds'] for b in bs),
            # 每场玩家方合计（伤害含护盾吸收与溢出；反击另计）
            'player_damage_dealt_avg': mean([sum(u['damage_dealt'] for u in b['units'] if u['faction'] == 'player') for b in bs]),
            'player_damage_taken_avg': mean([sum(u['damage_taken'] for u in b['units'] if u['faction'] == 'player') for b in bs]),
            'player_deaths': sum(1 for u in players if u['died_round']),
            'memory_not_applied': sum(1 for b in bs if not b.get('memory_applied', True)),
        })

    # 每个单位类型（分回忆配置）的动作分布与剑气流向，按每场平均
    unit_profiles = {}
    for (lineup, memory), bs in by_config.items():
        for b in bs:
            for u in b['units']:
                # 玩家按回忆配置分组；敌人按阵容分组（同一种哥布林在不同队友旁的行为分开看）
                group = memory if u['faction'] == 'player' else lineup
                key = '%s|%s' % (u['unit_id'], group)
                p = unit_profiles.setdefault(key, {'unit_id': u['unit_id'], 'group': group,
                                                    'faction': u['faction'], 'samples': 0, 'actions': collections.Counter(),
                                                    'failed_actions': collections.Counter(), 'qi': collections.Counter(),
                                                    'qi_capped': collections.Counter(), 'held_at_cap': collections.Counter(),
                                                    'turns': 0, 'extra_turns': 0, 'idle_turns': 0, 'suspicious_idle': 0,
                                                    'damage_dealt': 0, 'counter_damage_dealt': 0, 'damage_taken': 0})
                p['samples'] += 1
                for k in ('actions', 'failed_actions', 'qi', 'qi_capped', 'held_at_cap'):
                    p[k].update(u.get(k, {}))
                for k in ('turns', 'extra_turns', 'idle_turns', 'suspicious_idle', 'damage_dealt',
                          'counter_damage_dealt', 'damage_taken'):
                    p[k] += u.get(k, 0)
    profiles = []
    for key, p in sorted(unit_profiles.items()):
        n = p['samples']
        profiles.append({
            'unit_id': p['unit_id'], 'group': p['group'], 'faction': p['faction'], 'samples': n,
            'actions_per_battle': {k: round(v / n, 2) for k, v in p['actions'].most_common()},
            'failed_actions_per_battle': {k: round(v / n, 2) for k, v in p['failed_actions'].most_common()},
            # 分母是全部回合（含被控制跳过的）
            'actions_per_turn': round(sum(v for k, v in p['actions'].items() if k != 'move') / max(1, p['turns']), 2),
            'qi_per_battle': {k: round(v / n, 1) for k, v in sorted(p['qi'].items(), key=lambda kv: -abs(kv[1]))},
            'qi_capped_per_battle': {k: round(v / n, 1) for k, v in p['qi_capped'].most_common()},
            'held_at_cap_turns_per_battle': {k: round(v / n, 2) for k, v in p['held_at_cap'].most_common()},
            'extra_turns_per_battle': round(p['extra_turns'] / n, 2),
            'idle_turn_rate': round(p['idle_turns'] / max(1, p['turns']), 3),
            'suspicious_idle': p['suspicious_idle'],
            'damage_dealt_avg': round(p['damage_dealt'] / n, 1),
            'counter_damage_dealt_avg': round(p['counter_damage_dealt'] / n, 1),
            'damage_taken_avg': round(p['damage_taken'] / n, 1),
        })

    # AI 动作明细：每种单位每种动作的成功率、平均伤害、打〔影〕的比例
    action_stats = {}
    for a in actions:
        if a['action'] == 'move':
            continue
        key = '%s|%s' % (a['actor'], a['action'])
        s = action_stats.setdefault(key, {'actor': a['actor'], 'action': a['action'], 'count': 0, 'executed': 0,
                                          'damage': 0, 'counter_damage': 0, 'on_illusion': 0, 'no_target': 0})
        s['count'] += 1
        s['executed'] += 1 if a['executed'] else 0
        s['damage'] += a['damage']
        s['counter_damage'] += a['counter_damage']
        s['on_illusion'] += 1 if a.get('target_illusion') else 0
        s['no_target'] += 1 if not a.get('target') else 0
    action_list = []
    for s in sorted(action_stats.values(), key=lambda x: (x['actor'], -x['count'])):
        action_list.append({'actor': s['actor'], 'action': s['action'], 'count': s['count'],
                            'success_rate': round(s['executed'] / s['count'], 3),
                            'damage_avg': round(s['damage'] / s['count'], 2),
                            'counter_damage_avg': round(s['counter_damage'] / s['count'], 2),
                            'illusion_target_rate': round(s['on_illusion'] / s['count'], 3),
                            'no_unit_target_rate': round(s['no_target'] / s['count'], 3)})

    event_groups = {}
    for e in events:
        g = event_groups.setdefault(e['kind'], {'count': 0, 'examples': []})
        g['count'] += 1
        if len(g['examples']) < 8:
            g['examples'].append(e)

    summary = {
        'battles': len(battles), 'configs': configs, 'unit_profiles': profiles, 'actions': action_list,
        'status_damage_avg': mean([b.get('status_damage', 0) for b in battles]),
        'events': event_groups, 'log_messages': parse_log(os.path.join(out_dir, 'godot.log')),
    }
    with open(os.path.join(out_dir, 'summary.json'), 'w', encoding='utf-8') as f:
        json.dump(summary, f, ensure_ascii=False, indent=1)
    print('battles=%d configs=%d events=%d log_kinds=%d' % (
        len(battles), len(configs), len(events), len(summary['log_messages'])))


if __name__ == '__main__':
    main(sys.argv[1])
