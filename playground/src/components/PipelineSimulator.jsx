import React, { useState, useMemo, useEffect } from 'react';
import { simulateJobLifecycle } from '../lib/simulation.js';
import { SCENARIOS, shortenAddress } from '../lib/utils.js';
import LifecycleStep from './LifecycleStep.jsx';
import ParameterPanel from './ParameterPanel.jsx';

const VERDICT_CONFIG = {
  approved: { label: 'Completed', dot: '#10b981', desc: 'Job completed. Payment released. EAS attestation minted. Reputation updated.' },
  rejected: { label: 'Rejected', dot: '#ef4444', desc: 'Hook reverted. Job blocked or rejected by evaluator. Client refunded.' },
  escalated: { label: 'Escalated', dot: '#f59e0b', desc: 'Provider needs quorum consensus. Job awaiting multi-judge review.' },
};

export default function PipelineSimulator({ params, onParamsChange, compare }) {
  const [scenarioIdx, setScenarioIdx] = useState(0);
  const [animKey, setAnimKey] = useState(0);

  const scenario = SCENARIOS[scenarioIdx];
  const result = useMemo(
    () => simulateJobLifecycle({
      client: scenario.client,
      provider: scenario.provider,
      evaluator: scenario.evaluator,
      budget: scenario.budget,
      paymentToken: scenario.token,
      params,
    }),
    [scenario, params]
  );

  useEffect(() => { setAnimKey((k) => k + 1); }, [scenarioIdx, params]);
  const vc = VERDICT_CONFIG[result.verdict];

  return (
    <div className="flex flex-col lg:flex-row gap-6">
      <div className="flex-1 min-w-0">
        {/* Scenario selector */}
        <div className="rounded-xl p-5 mb-6" style={{ background: 'var(--card-bg)', border: '1px solid var(--border-color)' }}>
          <div className="text-[9px] font-bold uppercase tracking-[0.2em] mb-3" style={{ color: 'var(--text-muted)' }}>
            ERC-8183 Job Scenario
          </div>
          <div className="flex flex-wrap gap-2 mb-4">
            {SCENARIOS.map((s, i) => (
              <button
                key={s.label}
                onClick={() => setScenarioIdx(i)}
                className="text-[10px] font-medium px-3 py-1.5 rounded-full transition-all"
                style={{
                  color: i === scenarioIdx ? 'var(--text-color)' : 'var(--text-muted)',
                  background: i === scenarioIdx ? 'var(--badge-bg)' : 'transparent',
                  border: `1px solid ${i === scenarioIdx ? 'var(--border-color)' : 'transparent'}`,
                }}
              >
                {s.label}
              </button>
            ))}
          </div>
          <p className="text-[11px] mb-3" style={{ color: 'var(--text-secondary)' }}>{scenario.desc}</p>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-[10px]">
            <div>
              <div className="font-bold uppercase tracking-wider mb-0.5" style={{ color: 'var(--text-muted)' }}>Client</div>
              <div className="font-mono" style={{ color: 'var(--text-color)' }}>{shortenAddress(scenario.client)}</div>
            </div>
            <div>
              <div className="font-bold uppercase tracking-wider mb-0.5" style={{ color: 'var(--text-muted)' }}>Provider</div>
              <div className="font-mono" style={{ color: 'var(--text-color)' }}>{shortenAddress(scenario.provider)}</div>
            </div>
            <div>
              <div className="font-bold uppercase tracking-wider mb-0.5" style={{ color: 'var(--text-muted)' }}>Budget</div>
              <div className="font-mono" style={{ color: 'var(--text-color)' }}>${scenario.budget.toLocaleString()} {scenario.token}</div>
            </div>
            <div>
              <div className="font-bold uppercase tracking-wider mb-0.5" style={{ color: 'var(--text-muted)' }}>Hook</div>
              <div className="font-mono" style={{ color: 'var(--text-color)' }}>MaiatRouter</div>
            </div>
          </div>
        </div>

        {/* Job Lifecycle */}
        <div className="mb-3">
          <div className="text-[9px] font-bold uppercase tracking-[0.2em] mb-3" style={{ color: 'var(--text-muted)' }}>
            AgenticCommerceHooked — Job Lifecycle
          </div>
        </div>

        <div key={animKey}>
          {result.lifecycle.map((step, i) => (
            <div key={step.step + i}>
              <LifecycleStep step={step} index={i} animate={true} />
              {i < result.lifecycle.length - 1 && <div className="pipeline-connector" />}
            </div>
          ))}
        </div>

        {/* Final Verdict */}
        <div className="pipeline-connector" />
        <div
          className="rounded-xl p-8 text-center hook-animate"
          style={{
            animationDelay: `${result.lifecycle.length * 300}ms`,
            background: 'var(--card-bg)',
            border: `1px solid ${vc.dot}25`,
            boxShadow: `0 0 40px ${vc.dot}08`,
          }}
        >
          <div className="flex items-center justify-center gap-3 mb-2">
            <div className="w-3 h-3 rounded-full" style={{ background: vc.dot }} />
            <span className="atmosphere-text text-3xl sm:text-4xl">{vc.label}.</span>
          </div>
          <p className="text-xs mt-2" style={{ color: 'var(--text-secondary)' }}>{vc.desc}</p>
        </div>
      </div>

      {/* Sidebar */}
      {!compare && (
        <div className="w-full lg:w-64 shrink-0">
          <div className="lg:sticky lg:top-24">
            <ParameterPanel params={params} onChange={onParamsChange} />

            {/* Hook architecture note */}
            <div className="rounded-xl p-4 mt-4" style={{ background: 'var(--card-bg)', border: '1px solid var(--border-color)' }}>
              <div className="text-[9px] font-bold uppercase tracking-[0.2em] mb-2" style={{ color: 'var(--text-muted)' }}>
                Architecture
              </div>
              <div className="text-[10px] space-y-1.5 font-mono" style={{ color: 'var(--text-secondary)' }}>
                <p>MaiatRouterHook</p>
                <p className="pl-3">├ TrustGateACPHook</p>
                <p className="pl-3">├ TokenSafetyHook</p>
                <p className="pl-3">├ FundTransferHook</p>
                <p className="pl-3">├ AttestationHook</p>
                <p className="pl-3">└ MutualAttestationHook</p>
                <p className="mt-2">TrustBasedEvaluator</p>
                <p>EvaluatorRegistry</p>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
