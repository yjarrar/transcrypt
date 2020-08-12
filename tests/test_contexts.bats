#!/usr/bin/env bats

load $BATS_TEST_DIRNAME/_test_helper.bash

SECRET_CONTENT="My secret content"
SECRET_CONTENT_ENC="U2FsdGVkX1/kkWK36bn3fbq5DY2d+JXL2YWoN/eoXA1XJZEk9JS7j/856rXK9gPn"
SUPER_SECRET_CONTENT_ENC="U2FsdGVkX1+dAkIV/LAKXMmqjDNOGoOVK8Rmhw9tUnbR4dwBDglpkXIT3yzYBvoc"

function setup {
  pushd $BATS_TEST_DIRNAME
  init_git_repo
  init_transcrypt

  # Init transcrypt with 'super-secret' context
  $BATS_TEST_DIRNAME/../transcrypt --context=super-secret --cipher=aes-256-cbc --password=321cba --yes
}

function teardown {
  cleanup_all
  rm -f $BATS_TEST_DIRNAME/super_sensitive_file
  popd
}

@test "contexts: check validation of context names" {
  # Invalid context names
  run ../transcrypt --context=-ab --cipher=aes-256-cbc --password=none --yes
  [ "$status" -ne 0 ]
  run ../transcrypt --context=1ab --cipher=aes-256-cbc --password=none --yes
  [ "$status" -ne 0 ]
  run ../transcrypt --context=a--b --cipher=aes-256-cbc --password=none --yes
  [ "$status" -ne 0 ]
  run ../transcrypt --context=a- --cipher=aes-256-cbc --password=none --yes
  [ "$status" -ne 0 ]
  run ../transcrypt --context=A --cipher=aes-256-cbc --password=none --yes
  [ "$status" -ne 0 ]
  run ../transcrypt --context=aB --cipher=aes-256-cbc --password=none --yes
  [ "$status" -ne 0 ]
  run ../transcrypt --context=a-B --cipher=aes-256-cbc --password=none --yes
  [ "$status" -ne 0 ]

  # Valid context names
  run ../transcrypt --context=ab --cipher=aes-256-cbc --password=none --yes
  [ "$status" -eq 0 ]
  run ../transcrypt --context=a1 --cipher=aes-256-cbc --password=none --yes
  [ "$status" -eq 0 ]
  run ../transcrypt --context=a-b --cipher=aes-256-cbc --password=none --yes
  [ "$status" -eq 0 ]
  run ../transcrypt --context=a-1 --cipher=aes-256-cbc --password=none --yes
  [ "$status" -eq 0 ]
  run ../transcrypt --context=a-b-c --cipher=aes-256-cbc --password=none --yes
  [ "$status" -eq 0 ]
  run ../transcrypt --context=a-1-c --cipher=aes-256-cbc --password=none --yes
  [ "$status" -eq 0 ]
  run ../transcrypt --context=a-b-c-d --cipher=aes-256-cbc --password=none --yes
  [ "$status" -eq 0 ]
  run ../transcrypt --context=a-1-c-d-2 --cipher=aes-256-cbc --password=none --yes
  [ "$status" -eq 0 ]
}

@test "contexts: check git config for 'super-secret' context" {
  VERSION=`../transcrypt -v | awk '{print $2}'`
  GIT_DIR=`git rev-parse --git-dir`

  [ `git config --get transcrypt.version` = $VERSION ]
  [ `git config --get transcrypt.super-secret.cipher` = "aes-256-cbc" ]
  [ `git config --get transcrypt.super-secret.password` = "321cba" ]

  # Use --git-common-dir if available (Git post Nov 2014) otherwise --git-dir
  if [ -d $(git rev-parse --git-common-dir) ]; then
    [ "$(git config --get filter.crypt.clean)" = '"$(git rev-parse --git-common-dir)"/crypt/clean %f' ]
    [ "$(git config --get filter.crypt.smudge)" = '"$(git rev-parse --git-common-dir)"/crypt/smudge %f' ]
    [ "$(git config --get diff.crypt.textconv)" = '"$(git rev-parse --git-common-dir)"/crypt/textconv' ]
    [ "$(git config --get merge.crypt.driver)" = '"$(git rev-parse --git-common-dir)"/crypt/merge %O %A %B %L %P' ]
  else
    [ "$(git config --get filter.crypt.clean)" = '"$(git rev-parse --git-dir)"/crypt/clean %f' ]
    [ "$(git config --get filter.crypt.smudge)" = '"$(git rev-parse --git-dir)"/crypt/smudge %f' ]
    [ "$(git config --get diff.crypt.textconv)" = '"$(git rev-parse --git-dir)"/crypt/textconv' ]
    [ "$(git config --get merge.crypt.driver)" = '"$(git rev-parse --git-dir)"/crypt/merge %O %A %B %L %P' ]
  fi

  [ `git config --get filter.crypt.required` = "true" ]
  [ `git config --get diff.crypt.cachetextconv` = "true" ]
  [ `git config --get diff.crypt.binary` = "true" ]
  [ `git config --get merge.renormalize` = "true" ]

  [ "$(git config --get alias.ls-crypt)" = "!git -c core.quotePath=false ls-files | git -c core.quotePath=false check-attr --stdin filter | awk 'BEGIN { FS = \":\" }; / crypt$/{ print \$1 }'" ]
}

@test "init: show extra context details in --display" {
  VERSION=`../transcrypt -v | awk '{print $2}'`

  run ../transcrypt -C super-secret --display
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "The current repository was configured using transcrypt version $VERSION" ]
  [ "${lines[1]}" = "and has the following configuration for context 'super-secret':" ]
  [ "${lines[5]}" = "  CONTEXT:  super-secret" ]
  [ "${lines[6]}" = "  CIPHER:   aes-256-cbc" ]
  [ "${lines[7]}" = "  PASSWORD: 321cba" ]
  [ "${lines[8]}" = "The repository has 2 contexts: default super-secret" ]
  [ "${lines[9]}" = "Copy and paste the following command to initialize a cloned repository for context 'super-secret':" ]
  [ "${lines[10]}" = "  transcrypt -C super-secret -c aes-256-cbc -p '321cba'" ]
}

@test "contexts: encrypt a file in default and 'super-secret' contexts" {
  encrypt_named_file sensitive_file "$SECRET_CONTENT"
  encrypt_named_file super_sensitive_file "$SECRET_CONTENT" "super-secret"

  # Confirm .gitattributes is configured for multiple contexts
  run cat .gitattributes
  [ "${lines[1]}" = '"sensitive_file" filter=crypt diff=crypt merge=crypt' ]
  [ "${lines[2]}" = '"super_sensitive_file" filter=crypt diff=crypt merge=crypt crypt-context=super-secret' ]
}

@test "contexts: confirm --list-contexts lists configured contexts not yet in .gitattributes" {
  # Confirm .gitattributes is not yet configured for multiple contexts
  run ../transcrypt --list-contexts
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = 'default (no patterns in .gitattributes)' ]
  [ "${lines[1]}" = 'super-secret (no patterns in .gitattributes)' ]
}

@test "contexts: confirm --list-contexts lists contexts with config status" {
  encrypt_named_file sensitive_file "$SECRET_CONTENT"
  encrypt_named_file super_sensitive_file "$SECRET_CONTENT" "super-secret"

  # Confirm .gitattributes is configured for multiple contexts
  run ../transcrypt --list-contexts
  [ "$status" -eq 0 ]
  [[ "${output}" = *'default'* ]]
  [[ "${output}" = *'super-secret'* ]]
}

@test "contexts: encrypted file contents in multiple context are decrypted in working copy" {
  encrypt_named_file sensitive_file "$SECRET_CONTENT"
  encrypt_named_file super_sensitive_file "$SECRET_CONTENT" "super-secret"

  run cat sensitive_file
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$SECRET_CONTENT" ]

  run cat super_sensitive_file
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$SECRET_CONTENT" ]
}

@test "contexts: encrypted file contents in multiple contexts are encrypted differently in git (via git show)" {
  encrypt_named_file sensitive_file "$SECRET_CONTENT"
  encrypt_named_file super_sensitive_file "$SECRET_CONTENT" "super-secret"

  run git show HEAD:sensitive_file --no-textconv
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$SECRET_CONTENT_ENC" ]

  run git show HEAD:super_sensitive_file --no-textconv
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$SUPER_SECRET_CONTENT_ENC" ]
}

@test "contexts: transcrypt --show-raw shows encrypted content for multiple contexts" {
  encrypt_named_file sensitive_file "$SECRET_CONTENT"
  encrypt_named_file super_sensitive_file "$SECRET_CONTENT" "super-secret"

  run ../transcrypt --show-raw sensitive_file
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "==> sensitive_file <==" ]
  [ "${lines[1]}" = "$SECRET_CONTENT_ENC" ]

  run ../transcrypt --show-raw super_sensitive_file
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "==> super_sensitive_file <==" ]
  [ "${lines[1]}" = "$SUPER_SECRET_CONTENT_ENC" ]
}

@test "contexts: git ls-crypt lists encrypted file for all contexts" {
  encrypt_named_file sensitive_file "$SECRET_CONTENT"
  encrypt_named_file super_sensitive_file "$SECRET_CONTENT" "super-secret"

  run git ls-crypt
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "sensitive_file" ]
  [ "${lines[1]}" = "super_sensitive_file" ]
}

@test "contexts: git ls-crypt-default lists encrypted file for only 'default' context" {
  encrypt_named_file sensitive_file "$SECRET_CONTENT"
  encrypt_named_file super_sensitive_file "$SECRET_CONTENT" "super-secret"

  run git ls-crypt-default
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "sensitive_file" ]
  [ "${lines[1]}" = "" ]
}

@test "contexts: git ls-crypt-super-secret lists encrypted file for only 'super-secret' context" {
  encrypt_named_file sensitive_file "$SECRET_CONTENT"
  encrypt_named_file super_sensitive_file "$SECRET_CONTENT" "super-secret"

  run git ls-crypt-super-secret
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "super_sensitive_file" ]
  [ "${lines[1]}" = "" ]
}

@test "contexts: transcrypt --list lists encrypted files for all contexts" {
  encrypt_named_file sensitive_file "$SECRET_CONTENT"
  encrypt_named_file super_sensitive_file "$SECRET_CONTENT" "super-secret"

  run ../transcrypt --list
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "sensitive_file" ]
  [ "${lines[1]}" = "super_sensitive_file" ]
  [ "${lines[2]}" = "" ]
}

@test "contexts: transcrypt --uninstall leaves decrypted files and repo dirty for all contexts" {
  encrypt_named_file sensitive_file "$SECRET_CONTENT"
  encrypt_named_file super_sensitive_file "$SECRET_CONTENT" "super-secret"

  run ../transcrypt --uninstall --yes
  [ "$status" -eq 0 ]

  run cat sensitive_file
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$SECRET_CONTENT" ]

  run cat super_sensitive_file
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$SECRET_CONTENT" ]

  run cat .gitattributes
  [ "${lines[0]}" = "" ]

  run check_repo_is_clean
  [ "$status" -ne 0 ]
}

@test "contexts: git reset after uninstall leaves encrypted file for all contexts" {
  encrypt_named_file sensitive_file "$SECRET_CONTENT"
  encrypt_named_file super_sensitive_file "$SECRET_CONTENT" "super-secret"

  ../transcrypt --uninstall --yes

  git reset --hard
  check_repo_is_clean

  run cat sensitive_file
  [ "$status" -eq 0 ]
  [ "${lines[0]}" != "$SECRET_CONTENT" ]
  [ "${lines[0]}" = "$SECRET_CONTENT_ENC" ]

  run cat super_sensitive_file
  [ "$status" -eq 0 ]
  [ "${lines[0]}" != "$SECRET_CONTENT" ]
  [ "${lines[0]}" = "$SUPER_SECRET_CONTENT_ENC" ]
}

@test "contexts: only one of multiple contexts can be configured at a time" {
  # Init transcrypt with encrypted files then reset to be like a new clone
  encrypt_named_file sensitive_file "$SECRET_CONTENT"
  encrypt_named_file super_sensitive_file "$SECRET_CONTENT" "super-secret"
  ../transcrypt --uninstall --yes
  git reset --hard
  check_repo_is_clean

  # Confirm sensitive files for both contexts are encrypted in working dir
  run cat sensitive_file
  [ "${lines[0]}" = "$SECRET_CONTENT_ENC" ]
  run cat super_sensitive_file
  [ "${lines[0]}" = "$SUPER_SECRET_CONTENT_ENC" ]

  # Confirm .gitattributes is configured for contexts, but Git is not
  run ../transcrypt --list-contexts
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = 'default (not initialised)' ]
  [ "${lines[1]}" = 'super-secret (not initialised)' ]

  # Re-init only super-secret context: its files are decrypted, not default context
  $BATS_TEST_DIRNAME/../transcrypt --context=super-secret --cipher=aes-256-cbc --password=321cba --yes
  run ../transcrypt --list-contexts
  [[ "${output}" = *'super-secret'* ]]
  run cat super_sensitive_file
  [ "${lines[0]}" = "$SECRET_CONTENT" ]
  run cat sensitive_file
  [ "${lines[0]}" = "$SECRET_CONTENT_ENC" ]

  # Reset again
  ../transcrypt --uninstall --yes
  git reset --hard
  check_repo_is_clean

  # Re-init only default context: its files are decrypted, not super-secret context
  $BATS_TEST_DIRNAME/../transcrypt --cipher=aes-256-cbc --password=abc123 --yes
  run ../transcrypt --list-contexts
  [[ "${output}" = *'default'* ]]
  run cat sensitive_file
  [ "${lines[0]}" = "$SECRET_CONTENT" ]
  run cat super_sensitive_file
  [ "${lines[0]}" = "$SUPER_SECRET_CONTENT_ENC" ]
}
