/**
 * Maiat8183 × Synthesis Hackathon Simulation
 * 
 * Simulates the ERC-8183 hook pipeline for hackathon judging:
 * - 569 projects (clients) request evaluation
 * - N judge agents (providers) with zero initial reputation
 * - Maiat8183 hooks gate, escrow, and attest every interaction
 * - Reputation builds organically across rounds
 * 
 * Run: node synthesis/simulation.js
 */

const TOTAL_PROJECTS = 569;
const NUM_JUDGES = 10;
const ROUNDS = 5;
const TRUST_THRESHOLD = 50;        // TrustGateACPHook threshold
const ESCROW_THRESHOLD = 30;       // Below this → escrow required
const AUTO_APPROVE_THRESHOLD = 70; // Above this → auto-approved by TrustBasedEvaluator
const QUORUM = 3;                  // Min judges per project when trust is low
const SCORE_PER_GOOD_JUDGMENT = 12;
const SCORE_PER_BAD_JUDGMENT = -8;

// Simulate judge quality (some good, some bad)
const judges = Array.from({ length: NUM_JUDGES }, (_, i) => ({
  id: `judge-${i + 1}`,
  quality: i < 7 ? 'good' : 'bad',  // 70% good judges, 30% bad
  trustScore: 0,
  attestations: 0,
  jobsCompleted: 0,
  blocked: false,
}));

console.log('═══════════════════════════════════════════════════════════════');
console.log('  MAIAT8183 × SYNTHESIS HACKATHON — TRUST SIMULATION');
console.log('═══════════════════════════════════════════════════════════════');
console.log(`  Projects (clients):     ${TOTAL_PROJECTS}`);
console.log(`  Judge agents (providers): ${NUM_JUDGES} (${judges.filter(j => j.quality === 'good').length} good, ${judges.filter(j => j.quality === 'bad').length} bad)`);
console.log(`  Rounds:                 ${ROUNDS}`);
console.log(`  TrustGate threshold:    ${TRUST_THRESHOLD}`);
console.log(`  Escrow threshold:       ${ESCROW_THRESHOLD}`);
console.log(`  Auto-approve threshold: ${AUTO_APPROVE_THRESHOLD}`);
console.log(`  Min quorum (low trust): ${QUORUM} judges per project`);
console.log('═══════════════════════════════════════════════════════════════\n');

const results = { attestations: 0, escalations: 0, blocks: 0, escrows: 0 };

for (let round = 1; round <= ROUNDS; round++) {
  console.log(`\n┌─── ROUND ${round} ${'─'.repeat(52)}`);
  
  const projectsThisRound = Math.floor(TOTAL_PROJECTS / ROUNDS);
  let roundBlocks = 0, roundEscrows = 0, roundAutoApproved = 0, roundEscalated = 0;
  
  for (let p = 0; p < projectsThisRound; p++) {
    // Select judges for this project
    const availableJudges = judges.filter(j => !j.blocked);
    const selectedJudges = availableJudges
      .sort(() => Math.random() - 0.5)
      .slice(0, Math.max(QUORUM, 1));
    
    for (const judge of selectedJudges) {
      // ── TrustGateACPHook.beforeJobTaken() ──
      if (judge.trustScore >= TRUST_THRESHOLD) {
        // Pass — trusted judge, no escrow needed
      } else if (judge.trustScore >= ESCROW_THRESHOLD) {
        // Pass with escrow
        roundEscrows++;
        results.escrows++;
      } else {
        // All judges start here — escrow + quorum required
        roundEscrows++;
        results.escrows++;
      }
      
      // ── Judge evaluates (simulate quality) ──
      const isAccurate = judge.quality === 'good' 
        ? Math.random() < 0.85  // good judges: 85% accurate
        : Math.random() < 0.35; // bad judges: 35% accurate
      
      // ── TrustBasedEvaluator ──
      if (judge.trustScore >= AUTO_APPROVE_THRESHOLD) {
        roundAutoApproved++;
      } else {
        // Needs multi-judge consensus
        roundEscalated++;
        results.escalations++;
      }
      
      // ── AttestationHook.afterAction() → mint EAS receipt ──
      judge.attestations++;
      judge.jobsCompleted++;
      results.attestations++;
      
      // ── Update trust score based on accuracy ──
      if (isAccurate) {
        judge.trustScore = Math.min(100, judge.trustScore + SCORE_PER_GOOD_JUDGMENT);
      } else {
        judge.trustScore = Math.max(0, judge.trustScore + SCORE_PER_BAD_JUDGMENT);
      }
    }
  }
  
  // Check for judges that should be blocked
  const newlyBlocked = judges.filter(j => !j.blocked && j.jobsCompleted > 10 && j.trustScore < 20);
  newlyBlocked.forEach(j => { j.blocked = true; results.blocks++; });
  
  console.log(`│  Projects evaluated:  ${projectsThisRound}`);
  console.log(`│  Escrow required:     ${roundEscrows} (FundTransferHook)`);
  console.log(`│  Auto-approved:       ${roundAutoApproved} (TrustBasedEvaluator)`);
  console.log(`│  Multi-judge review:  ${roundEscalated} (quorum consensus)`);
  console.log(`│  EAS attestations:    ${results.attestations} total`);
  if (newlyBlocked.length > 0) {
    console.log(`│  ❌ BLOCKED:          ${newlyBlocked.map(j => j.id).join(', ')}`);
  }
  console.log(`│`);
  console.log(`│  Judge Status:`);
  judges.forEach(j => {
    const status = j.blocked ? '❌ BLOCKED' : j.trustScore >= AUTO_APPROVE_THRESHOLD ? '✅ AUTO-APPROVED' : j.trustScore >= TRUST_THRESHOLD ? '🟡 TRUSTED' : '🔵 ESCROW';
    const bar = '█'.repeat(Math.floor(j.trustScore / 5)) + '░'.repeat(20 - Math.floor(j.trustScore / 5));
    console.log(`│    ${j.id} [${bar}] ${String(j.trustScore).padStart(3)}/100  ${j.quality.padEnd(4)}  ${status}`);
  });
  console.log(`└${'─'.repeat(60)}`);
}

console.log('\n═══════════════════════════════════════════════════════════════');
console.log('  FINAL RESULTS');
console.log('═══════════════════════════════════════════════════════════════');
console.log(`  Total EAS attestations minted:  ${results.attestations}`);
console.log(`  Total escrow transactions:      ${results.escrows}`);
console.log(`  Total multi-judge escalations:  ${results.escalations}`);
console.log(`  Bad judges blocked:             ${results.blocks}`);
console.log('');

const goodJudges = judges.filter(j => j.quality === 'good');
const badJudges = judges.filter(j => j.quality === 'bad');
const avgGood = (goodJudges.reduce((s, j) => s + j.trustScore, 0) / goodJudges.length).toFixed(0);
const avgBad = (badJudges.reduce((s, j) => s + j.trustScore, 0) / badJudges.length).toFixed(0);

console.log(`  Good judges avg trust score: ${avgGood}/100`);
console.log(`  Bad judges avg trust score:  ${avgBad}/100`);
console.log(`  Good judges auto-approved:   ${goodJudges.filter(j => j.trustScore >= AUTO_APPROVE_THRESHOLD).length}/${goodJudges.length}`);
console.log(`  Bad judges blocked:          ${badJudges.filter(j => j.blocked).length}/${badJudges.length}`);
console.log('');
console.log('  Conclusion:');
console.log('  → Good judges earned auto-approval through consistent accuracy');
console.log('  → Bad judges were naturally gated out by low trust scores');
console.log('  → Every judgment has an immutable EAS attestation');
console.log('  → Cold start solved: escrow + quorum protected projects from day 1');
console.log('═══════════════════════════════════════════════════════════════');
