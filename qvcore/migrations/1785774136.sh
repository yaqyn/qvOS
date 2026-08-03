echo "Retire the duplicate Windows runtime source copy"

runtime_root="$HOME/.local/lib/qvos/windows"
runtime_parent=${runtime_root%/*}
safe_parent=true
for parent in \
  "$HOME/.local" \
  "$HOME/.local/lib" \
  "$runtime_parent"; do
  if [[ ! -d $parent || -L $parent || ! -O $parent ]]; then
    safe_parent=false
    break
  fi
done

if [[ -e $runtime_root || -L $runtime_root ]]; then
  declare -A expected_hashes=(
    [AGENTS.md]='18c74a52fe96ec5bd9bfc1432b2fe4c74128d23c781f7759ceb98e5d147c263d 2101f363f64b66745c645dbe551bae73794f00e349e65ee8860783e8e7815e9f'
    [command]='bd9bbb29cf6f0954813793521d93146354fff32698b24bd0806ab972d48c94f9'
    [launch]='147856caebbe3af99ecaa31d448f53f05cf2670595c2ed95898aaea3dc98083e'
    [lib]='65c4375c1cf217673d7fc9a7136fc18ac55e89cb25065a7bd16bde312dfe3327'
    [manage]='f44026d4d79d597b2555e7a2e56fb9a1a43d8d27f2e583d1b2af0fe2f2676bfc'
  )
  runtime_safe=$safe_parent
  runtime_count=0

  if [[ ! -d $runtime_root || -L $runtime_root || ! -O $runtime_root ]]; then
    runtime_safe=false
  else
    while IFS= read -r -d '' runtime_entry; do
      ((runtime_count += 1))
      runtime_name=${runtime_entry##*/}
      if [[ -z ${expected_hashes[$runtime_name]:-} ||
        ! -f $runtime_entry || -L $runtime_entry || ! -O $runtime_entry ]]; then
        runtime_safe=false
        continue
      fi
      runtime_hash=$(sha256sum -- "$runtime_entry")
      runtime_hash=${runtime_hash%% *}
      if [[ " ${expected_hashes[$runtime_name]} " != *" $runtime_hash "* ]]; then
        runtime_safe=false
      fi
    done < <(find -P "$runtime_root" -mindepth 1 -maxdepth 1 -print0)
  fi

  if [[ $runtime_safe == "true" ]] && ((runtime_count == ${#expected_hashes[@]})); then
    for runtime_name in "${!expected_hashes[@]}"; do
      rm -f -- "$runtime_root/$runtime_name"
    done
    rmdir -- "$runtime_root"
  else
    echo "Preserving modified or unsafe retired Windows runtime: $runtime_root" >&2
  fi
fi
