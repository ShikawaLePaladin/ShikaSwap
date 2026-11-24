#!/bin/sh
# Lint 5.0 (existing tool) + unit/scenario tests (new harness) + evidence run of the OLD addon. Run from this folder.
set -e
cd "$(dirname "$0")"
for f in ShikaSwap/ShikaSwap_Data.lua ShikaSwap/ShikaSwap_Core.lua ShikaSwap/ShikaSwap_Hooks.lua ShikaSwap/ShikaSwap_Cmd.lua ShikaSwap/ShikaSwap_Trace.lua ShikaSwap/ShikaSwap_Spec.lua ShikaSwap/ShikaSwap_Share.lua ShikaSwap/ShikaSwap_Display.lua ShikaSwap/ShikaSwap_Bindings.lua ShikaSwap/ShikaSwap_UI.lua; do
  echo "== lint50 $f"; node C:/Temp/ccx/luatest/lint50.js "$f"
  echo -n "   "; node tools/lint_upvalues.js "$f" | grep "max upvalues"
done
echo "== tests (core, hooks, commands)"; node tests/harness_shikaswap.js tests/tests_shikaswap.lua | tail -3
echo "== tests (menu, minimap, indicator, alert, specs, export/import, bindings)"; node tests/harness_shikaswap.js tests/tests_ui.lua | tail -3
echo "== tests (1.2.0 : Necroladin, profile bar, theme, icons, migration)"; node tests/harness_shikaswap.js tests/tests_v12.lua | tail -3
echo "== tests (1.3.0 : persistent trace, off-GCD policy, queue, migration)"; node tests/harness_shikaswap.js tests/tests_v13.lua | tail -3
echo "== tests (exec relic : Final Judgement + verrou)"; node tests/harness_shikaswap.js tests/tests_exec.lua | tail -3
echo "== old addon evidence (read-only run of the old core in the mock world)"
KEEP_G=1 FILES="C:/MesJeuxRare/octowow/Interface/AddOns/LibramSwap/LibramSwap_fixed.lua" node tests/harness_shikaswap.js tests/audit_old.lua > tests/audit_old_output.txt && echo "   written tests/audit_old_output.txt"
