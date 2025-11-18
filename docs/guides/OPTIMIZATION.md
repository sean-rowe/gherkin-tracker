# Agent System Optimization Strategies

## Current Performance
- **~2-3 minutes per task**
- 12,534 tasks = ~420 hours (~17.5 days) of continuous running

## Bottlenecks

### 1. Claude Code Overhead (24s/task)
- Loads project context each call
- Called twice per task (BDD + business logic)

### 2. Implementation Time (30-120s/task)
- Actual code generation
- File I/O

### 3. Build/Test (20-60s/task)
- .NET compilation
- Test execution

## Optimization Options

### Option 1: **Combine Prompts** (RECOMMENDED)
Instead of calling Claude twice, use ONE prompt for both BDD step and business logic.

**Savings**: ~12 seconds per task (removes one Claude startup)
**Implementation**: Easy - merge the two prompts

```python
combined_prompt = f"""
Implement both the SpecFlow BDD step definition AND the business logic for this step:

Feature: {feature_name}
Scenario: {scenario_name}
Step: {step_type} {step_text}

Tasks:
1. Create/update BDD step definition in tests/CareSync.Specs/StepDefinitions/
2. Create/update business logic service in src/3-Infrastructure/.../Services/
3. Ensure they work together

[rest of requirements...]
"""
```

### Option 2: **Batch Building**
Build and test only after N tasks, not after each one.

**Savings**: ~30-50 seconds per task (build incrementally)
**Risk**: Errors accumulate, harder to debug
**Implementation**: Add `--skip-build` flag

### Option 3: **Incremental Builds**
Use `dotnet build --no-restore` and cache build artifacts.

**Savings**: ~10-20 seconds per task
**Implementation**: Moderate

### Option 4: **Parallel Agent Execution**
Run multiple agents simultaneously (different tasks).

**Savings**: 2x-4x speedup (limited by CPU/Claude API rate limits)
**Complexity**: High - need proper database locking
**Implementation**: Use Python multiprocessing

### Option 5: **Skip Tests During Development**
Only run tests every N tasks or at the end.

**Savings**: ~15-30 seconds per task
**Risk**: Quality issues detected late
**Implementation**: Add `--test-frequency` flag

### Option 6: **Use Fast Model for Simple Tasks**
Some tasks might work with Haiku instead of Sonnet.

**Savings**: Variable, but potentially 50% faster
**Implementation**: Would need API access, not CLI

## Recommended Approach

### Phase 1: Quick Wins (Implement Now)
1. **Combine prompts** - merge BDD + business logic into one Claude call
2. **Add --skip-tests flag** - build only, skip tests for development speed
3. **Incremental builds** - use `dotnet build --no-restore`

**Expected savings**: ~30-40 seconds per task → **~90 seconds per task**

### Phase 2: Advanced (Later)
4. **Batch testing** - test every 10 tasks instead of every task
5. **Parallel execution** - run 2-4 agents simultaneously

**Expected savings**: Additional 50% → **~45-60 seconds per task** with parallelism

### Phase 3: Production (When Deploying)
6. **Full tests always**
7. **Verification scanning**
8. **Quality gates**

## Implementation Priority

```python
# agent_claude.py --help output after optimizations:
python3 agent_claude.py \
    --max-tasks 100 \           # Limit tasks
    --combined-prompts \        # Use single Claude call (FASTER)
    --skip-tests \              # Skip test execution (MUCH FASTER)
    --test-every 10 \           # Test every 10th task only
    --parallel 4                # Run 4 agents in parallel (FASTEST)
```

## Time Estimates with Optimizations

| Configuration | Time/Task | 12,534 Tasks | Speedup |
|--------------|-----------|--------------|---------|
| Current | 150s | 17.5 days | 1x |
| Combined prompts | 138s | 16 days | 1.09x |
| + Skip tests | 90s | 10.4 days | 1.67x |
| + Parallel (4x) | 22.5s | 2.6 days | 6.67x |

## Code Changes Needed

See `agent_claude_optimized.py` for implementation of:
- Combined prompts
- Skip tests flag
- Batch testing
- Better progress reporting
