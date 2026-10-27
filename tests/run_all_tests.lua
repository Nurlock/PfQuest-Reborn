-- Main Test Runner for pfQuest-Reborn Regression Test Suite
-- Executes all test suites and verifies exit status.
-- Usage: lua5.1 tests/run_all_tests.lua

local suites = {
  "tests/test_questgiver_lifecycle.lua",
  "tests/test_objective_parsing.lua",
  "tests/test_metadata_isolation.lua",
  "tests/test_delete_node_fallback.lua",
  "tests/test_performance_guards.lua",
  "tests/test_config_dependencies.lua",
  "tests/test_wizard_lifecycle.lua",
  "tests/test_party_sync_and_tooltips.lua",
}

print("======================================================================")
print("  pfQuest-Reborn Regression Test Suite (Lua 5.1 / WoW 3.3.5a)")
print("======================================================================")

local passed = 0
local failed = 0
local startTime = os.clock()

for _, suitePath in ipairs(suites) do
  print("\n>>> Running " .. suitePath .. "...")
  local cmd = string.format("lua5.1 %s", suitePath)
  local status = os.execute(cmd)

  -- In Lua 5.1, os.execute returns the exit code directly (0 for success)
  local ok = (status == 0) or (status == true)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAILED: " .. suitePath)
  end
end

local elapsed = os.clock() - startTime
print("\n======================================================================")
print(string.format("  Test Summary: %d passed, %d failed in %.3fs", passed, failed, elapsed))
print("======================================================================")

if failed > 0 then
  os.exit(1)
else
  os.exit(0)
end
