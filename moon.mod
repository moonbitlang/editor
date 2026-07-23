name = "moonbit-community/editor"

version = "0.2.1"

readme = "README.md"

repository = "https://github.com/moonbit-community/editor"

license = "Apache-2.0"

keywords = [ "editor", "moonbit", "readonly", "syntax-highlighting" ]

description = "Readonly MoonBit code viewer harness inspired by Monaco and CodeMirror."

supported_targets = "+js+native"

preferred_target = "js"

import {
  "moonbit-community/cmark@0.4.4",
  "moonbitlang/async@0.20.1",
  "moonbit-community/rabbita@0.12.4",
  "moonbit-community/piediff@0.0.10",
  "Milky2018/diago@0.3.0",
}

options(
  exclude: [
    "codemirror",
    "vscode",
    "internal/shell",
    "tests",
    "scripts",
    "internal/viewer/ui/scrollbar/mouse_wheel_classifier_reference_wbtest.mbt",
    "AGENTS.md",
    "justfile",
    "package.json",
    "package-lock.json",
    "playwright.config.js",
    "docs/exec-plans",
    "docs/references",
    "docs/notes",
    "docs/styles.md",
  ],
)
