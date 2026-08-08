# Graph Report - setup-server  (2026-08-08)

## Corpus Check
- 1 files · ~4,685 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 24 nodes · 55 edges · 4 communities
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `176ea033`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- setup.sh script
- setup.sh
- configure_proxy
- log

## God Nodes (most connected - your core abstractions)
1. `setup.sh script` - 12 edges
2. `configure_proxy()` - 9 edges
3. `log_info()` - 6 edges
4. `log_warn()` - 6 edges
5. `log_error()` - 6 edges
6. `log()` - 5 edges
7. `log_success()` - 5 edges
8. `detect_os()` - 5 edges
9. `install_package()` - 4 edges
10. `check_root()` - 3 edges

## Surprising Connections (you probably didn't know these)
- `setup.sh script` --calls--> `check_disk_space()`  [EXTRACTED]
  setup.sh → setup.sh  _Bridges community 0 → community 3_
- `setup.sh script` --calls--> `configure_proxy()`  [EXTRACTED]
  setup.sh → setup.sh  _Bridges community 0 → community 2_
- `configure_proxy()` --calls--> `log_success()`  [EXTRACTED]
  setup.sh → setup.sh  _Bridges community 3 → community 2_

## Import Cycles
- None detected.

## Communities (4 total, 0 thin omitted)

### Community 0 - "setup.sh script"
Cohesion: 0.46
Nodes (8): check_internet(), check_root(), detect_os(), install_package(), log_error(), log_info(), progress(), setup.sh script

### Community 1 - "setup.sh"
Cohesion: 0.33
Nodes (5): BACKUP_DIR, CONFIG_DIR, LOG_FILE, PROJECT_FILE, PROXY_FILE

### Community 2 - "configure_proxy"
Cohesion: 0.50
Nodes (5): apply_proxy_session(), clear_git_proxy(), configure_proxy(), disable_proxy(), test_proxy()

### Community 3 - "log"
Cohesion: 0.40
Nodes (5): check_disk_space(), final_summary(), log(), log_success(), log_warn()

## Knowledge Gaps
- **5 isolated node(s):** `LOG_FILE`, `CONFIG_DIR`, `PROJECT_FILE`, `BACKUP_DIR`, `PROXY_FILE`
  These have ≤1 connection - possible missing edges or undocumented components.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `setup.sh script` connect `setup.sh script` to `setup.sh`, `configure_proxy`, `log`?**
  _High betweenness centrality (0.075) - this node is a cross-community bridge._
- **Why does `configure_proxy()` connect `configure_proxy` to `setup.sh script`, `setup.sh`, `log`?**
  _High betweenness centrality (0.044) - this node is a cross-community bridge._
- **Why does `log_error()` connect `setup.sh script` to `setup.sh`, `log`?**
  _High betweenness centrality (0.010) - this node is a cross-community bridge._
- **What connects `LOG_FILE`, `CONFIG_DIR`, `PROJECT_FILE` to the rest of the system?**
  _5 weakly-connected nodes found - possible documentation gaps or missing edges._