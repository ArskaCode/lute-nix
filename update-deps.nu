#!/usr/bin/env nu

def prefetch_hash [remote: string, revision: string] {
  let args = ["--url", $remote, "--rev", $revision]
  let result = (^nix-prefetch-git ...$args | from json)
  $result.sha256
}

def main [lute_path: string] {
  let repo_root = ($env.PWD | path expand)
  let lute_path = ($lute_path | path expand)
  let extern_dir = ($lute_path | path join "extern")
  let tunes = (ls $extern_dir | where name ends-with ".tune" | sort-by name)

  let deps = ($tunes | each { |t|
    let doc = (open --raw $t.name | from toml)
    let depinfo = $doc.dependency

    let name = $depinfo.name
    let remote = $depinfo.remote
    let revision = $depinfo.revision

    let sha256 = (prefetch_hash $remote $revision)

    {
      name: $name,
      url: $remote,
      revision: $revision,
      sha256: $sha256,
    }
  })

  let out_path = ($repo_root | path join "deps.json")
  $deps | sort-by name | to json | save -f $out_path
}
