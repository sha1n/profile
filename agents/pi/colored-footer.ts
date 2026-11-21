import { execFileSync } from 'node:child_process';
import { homedir } from 'node:os';
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';
import { truncateToWidth, visibleWidth } from '@earendil-works/pi-tui';

// Match ~/code/profile/agents/claude/statusline.sh (Solarized dark, 24-bit).
const bands = [[50, '220;50;47'], [30, '203;75;22'], [20, '181;137;0'], [0, '133;153;0']] as const;
const palette = ['38;139;210', '42;161;152', '108;113;196', '211;54;130'];
const paint = (rgb: string, s: string) => `\x1b[38;2;${rgb}m${s}\x1b[39m`;
const colors = new Map<string, string>();
function modelColor(name: string) {
  if (!colors.has(name)) {
    // POSIX cksum of the display name, without a trailing newline. Once per model, not per frame.
    let hash = 0;
    try { hash = Number(execFileSync('cksum', { input: name, encoding: 'utf8', timeout: 500 }).split(/\s+/)[0]); }
    catch { for (const c of name) hash = (Math.imul(31, hash) + c.charCodeAt(0)) >>> 0; }
    colors.set(name, palette[hash % palette.length]);
  }
  return colors.get(name)!;
}
function count(n: number) {
  if (n < 1000) return String(n);
  const scale = n < 1e6 ? 1000 : 1e6;
  return (n / scale).toFixed(n < 10 * scale ? 1 : 0) + (scale === 1000 ? 'k' : 'M');
}
export default function(pi: ExtensionAPI) {
  pi.on('session_start', (_, ctx) => {
    if (!ctx.hasUI) return;
    ctx.ui.setFooter((tui, theme, data) => {
      const sm = ctx.sessionManager;
      const dispose = data.onBranchChange(() => tui.requestRender());
      let cacheKey = '', stats = '', percent: number | null = null, window = 0;
      return { dispose, invalidate() {}, render(width) {
        const model = ctx.model;
        const key = JSON.stringify([sm.getLeafId(), sm.getEntryCount(), model?.provider, model?.id]);
        if (cacheKey !== key) {
          cacheKey = key;
          const usage = ctx.getContextUsage();
          percent = usage?.percent ?? null;
          window = usage?.contextWindow ?? model?.contextWindow ?? 0;
          let input=0, output=0, read=0, write=0, cost=0, hit: number | undefined;
          for (const e of sm.getEntries()) {
            const msg = e.type === 'message' ? e.message : undefined;
            const u = msg?.role === 'assistant' || msg?.role === 'toolResult' ? msg.usage :
              e.type === 'usage' || e.type === 'compaction' || e.type === 'branch_summary' ? e.usage : undefined;
            if (!u) continue;
            input += u.input; output += u.output; read += u.cacheRead; write += u.cacheWrite; cost += u.cost.total;
            if (msg?.role === 'assistant') { const total = u.input + u.cacheRead + u.cacheWrite; hit = total ? 100*u.cacheRead/total : undefined; }
          }
          const sub = model && (model.provider === 'kimi-coding' || ctx.modelRegistry.isUsingOAuth(model));
          stats = [input && `↑${count(input)}`, output && `↓${count(output)}`, read && `R${count(read)}`, write && `W${count(write)}`, (read || write) && hit != null && `CH${hit.toFixed(1)}%`, (cost || sub) && `$${cost.toFixed(3)}${sub ? ' (sub)' : ''}`].filter(Boolean).join(' ');
        }
        const dim = (s: string) => theme.fg('dim', s);
        const pct = percent == null ? null : Math.max(0, Math.min(100, Math.trunc(percent)));
        let context = dim(`CTX ?/${count(window)}`);
        if (pct !== null) {
          const rgb = bands.find(([min]) => pct >= min)![1], cells = Math.round(pct/10);
          context = `CTX ${paint(rgb, '█'.repeat(cells))}${paint('88;110;117', '░'.repeat(10-cells))} ${paint(rgb, `${pct}%`)}/${count(window)}`;
        }
        const name = model?.name || model?.id || 'no-model';
        const label = paint(modelColor(name), model?.id || 'no-model');
        const thinking = model?.reasoning ? dim(` • ${pi.getThinkingLevel()}`) : '';
        let right = label + thinking;
        let left = stats ? `${dim(stats)}  ${context}` : context;
        const provider = model && data.getAvailableProviderCount() > 1 ? dim(`(${model.provider}) `) : '';
        if (visibleWidth(left+provider+right)+2 <= width) right = provider + right;
        if (visibleWidth(left+right)+2 > width) left = context;
        const branch = data.getGitBranch(), session = sm.getSessionName(), cwd = sm.getCwd(), home = homedir();
        const dir = cwd === home || cwd.startsWith(home+'/') ? '~'+cwd.slice(home.length) : cwd;
        const lines = [dim(`${dir}${branch ? ` (${branch})` : ''}${session ? ` • ${session}` : ''}`), left+' '.repeat(Math.max(2,width-visibleWidth(left+right)))+right];
        const statuses = [...data.getExtensionStatuses()].sort(([a],[b]) => a.localeCompare(b)).map(([,v]) => v.replace(/\s+/g,' ').trim());
        if (statuses.length) lines.push(statuses.join(' '));
        return lines.map(s => truncateToWidth(s,width));
      }};
    });
  });
}
