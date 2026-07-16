#!/bin/bash

set -euo pipefail

# Live integration tests share test classes with model tests today. Keep CI
# deterministic by excluding the classes/method that call a real backend.
# Run `swift test` directly when intentionally exercising that backend.
swift test \
    --skip 'InsForgeAITests\.InsForgeAITests' \
    --skip 'InsForgeAITests\.ToolCallingTests/testChatCompletionWithToolCalling' \
    --skip 'InsForgeFunctionsTests\.InsForgeFunctionsTests' \
    --skip 'InsForgeRealtimeTests\.InsForgeRealtimeTests' \
    --skip 'InsForgeStorageTests\.InsForgeStorageTests'
