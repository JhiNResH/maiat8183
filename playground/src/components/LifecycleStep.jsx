import React from 'react';
import HookBadge from './HookCard.jsx';

const RESULT_CONFIG = {
  pass: { dot: '#10b981', glow: '0 0 30px rgba(16, 185, 129, 0.06)' },
  blocked: { dot: '#ef4444', glow: '0 0 30px rgba(239, 68, 68, 0.06)' },
  warn: { dot: '#f59e0b', glow: '0 0 30px rgba(245, 158, 11, 0.06)' },
};

const STATUS_LABELS = {
  'Open': '○',
  'Funded': '◉',
  'Submitted': '◉',
  'Completed': '●',
  'Rejected': '✕',
  'Escalated': '◎',
  'Post-Job': '↻',
};

export default function LifecycleStep({ step, index, animate }) {
  const cfg = RESULT_CONFIG[step.result] || RESULT_CONFIG.pass;

  return (
    <div
      className={`rounded-xl overflow-hidden transition-all ${animate ? 'hook-animate' : ''}`}
      style={{
        animationDelay: animate ? `${index * 300}ms` : undefined,
        background: 'var(--card-bg)',
        border: `1px solid var(--border-color)`,
        boxShadow: step.result !== 'pass' ? cfg.glow : undefined,
      }}
    >
      {/* Step header */}
      <div className="px-5 py-3 flex items-center justify-between" style={{ borderBottom: '1px solid var(--border-color)' }}>
        <div className="flex items-center gap-3">
          <span className="text-sm" style={{ color: cfg.dot }}>{STATUS_LABELS[step.status] || '○'}</span>
          <div>
            <span className="text-xs font-bold font-mono" style={{ color: 'var(--text-color)' }}>
              {step.step}
            </span>
            <span className="text-[10px] ml-2 font-mono" style={{ color: 'var(--text-muted)' }}>
              → {step.status}
            </span>
          </div>
        </div>
        {step.data?.transition && (
          <span className="text-[10px] font-mono" style={{ color: 'var(--text-secondary)' }}>
            {step.data.transition}
          </span>
        )}
      </div>

      {/* Action description */}
      <div className="px-5 py-3">
        <p className="text-[11px] mb-3" style={{ color: 'var(--text-secondary)' }}>{step.action}</p>

        {/* Hooks */}
        {step.hooks.length > 0 && (
          <div className="space-y-2">
            <div className="text-[9px] font-bold uppercase tracking-[0.2em] mb-2" style={{ color: 'var(--text-muted)' }}>
              MaiatRouterHook → {step.hooks.length} plugin{step.hooks.length > 1 ? 's' : ''} fired
            </div>
            {step.hooks.map((hook, i) => (
              <HookBadge key={i} hook={hook} />
            ))}
          </div>
        )}

        {/* Extra data */}
        {step.data && Object.keys(step.data).length > 0 && (
          <div className="mt-3 pt-3" style={{ borderTop: '1px solid var(--border-color)' }}>
            <div className="grid grid-cols-2 gap-x-4 gap-y-1">
              {Object.entries(step.data).filter(([k]) => k !== 'transition').map(([key, val]) => {
                if (typeof val === 'object' && val !== null) {
                  return (
                    <div key={key} className="col-span-2 text-[10px]">
                      <span style={{ color: 'var(--text-muted)' }}>{key}: </span>
                      <span className="font-mono" style={{ color: 'var(--text-secondary)' }}>
                        {val.address ? `${val.address.slice(0, 10)}… (score: ${val.trustScore})` : JSON.stringify(val)}
                      </span>
                    </div>
                  );
                }
                return (
                  <div key={key} className="text-[10px]">
                    <span style={{ color: 'var(--text-muted)' }}>{key}: </span>
                    <span className="font-mono" style={{ color: 'var(--text-secondary)' }}>{String(val)}</span>
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
