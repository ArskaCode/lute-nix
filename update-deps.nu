#!/usr/bin/env nu

def fail [msg: string] {
  error make { msg: $msg }
}

def prefetch_hash [remote: string, revision: string] {
  let args = ["--url", $remote, "--rev", $revision]
  let result = (^nix-prefetch-git ...$args | from json)
  $result.sha256
}

def main [
  --lute-path: string = ""
  --out: string = "deps.json"
] {
  let repo_root = ($env.PWD | path expand)
  let lute_path = if $lute_path != "" {
    ($lute_path | path expand)
  } else {
    fail "no Lute path provided and ./lute not found"
  }

  let extern_dir = ($lute_path | path join "extern")
  if not ($extern_dir | path exists) {
    fail $"extern/ not found at: ($extern_dir)"
  }

  let tunes = (ls $extern_dir | where name ends-with ".tune" | sort-by name)
  if ($tunes | is-empty) {
    fail $"no .tune files found in: ($extern_dir)"
  }

  let deps = ($tunes | each { |t|
    let doc = (open --raw $t.name | from toml)
    let depinfo = $doc.dependency

    let name = $depinfo.name
    let remote = $depinfo.remote
    let revision = $depinfo.revision
    if ($name | is-empty) or ($remote | is-empty) or ($revision | is-empty) {
      fail $"missing fields in: ($t.name)"
    }

    let sha256 = (prefetch_hash $remote $revision)

    {
      name: $name,
      url: $remote,
      revision: $revision,
      sha256: $sha256,
    }
  })

  let out_path = ($repo_root | path join $out)
  $deps | sort-by name | to json | save -f $out_path
}
