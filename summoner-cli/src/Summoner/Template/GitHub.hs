{-# LANGUAGE ViewPatterns #-}

{- |
Module                  : Summoner.Template.GitHub
Copyright               : (c) 2017-2020 Kowainik
SPDX-License-Identifier : MPL-2.0
Maintainer              : Kowainik <xrom.xkov@gmail.com>
Stability               : Stable
Portability             : Portable

This module contains template for GitHub related docs:

 * @.gitignore@ — static file with all Haskell related ignored files.
 * @.github/workflows/ci.yml@ — GitHub acttions for Cabal projects.
 * @appveyor.yml@ — Appveyor CI for Cabal or Stack projects.
 * @.travis.yml@ — depending on the build tool and supported GHC versions
   builds the Travis matrix with all necessary checks, including HLint check.
   __NOTE:__ Old GHC versions are included into @allow_failure@ Travis matrix
   section for Stack due to Stack limitations with the Cabal version usage on
   each GHC. See this issue to track the problem:

    + https://github.com/commercialhaskell/stack/issues/4488
-}

module Summoner.Template.GitHub
    ( gitHubFiles
    ) where

import Colourista (indent)
import Data.List (delete, intersect)

import Summoner.Default (defaultCabal, defaultGHC)
import Summoner.GhcVer (GhcVer (..), oldGhcs, showGhcVer)
import Summoner.Settings (Settings (..))
import Summoner.Text (quote)
import Summoner.Tree (TreeFs (..))


gitHubFiles :: Settings -> [TreeFs]
gitHubFiles Settings{..} = concat
    [ [File ".gitignore" (gitignoreDefault <> gitignoreCustom) | settingsGitHub]
    , [Dir ".github" [ Dir "workflows" [ File "ci.yml" ghActionsYml ]] | settingsGhActions ]
    , [File ".travis.yml" travisYml    | settingsTravis]
    , [File "appveyor.yml" appVeyorYml | settingsAppVeyor]
    ]
  where
    -- default .gitignore template
    gitignoreDefault :: Text
    gitignoreDefault = unlines
        [ "### Haskell"
        , "dist"
        , "dist-*"
        , "cabal-dev"
        , "*.o"
        , "*.hi"
        , "*.chi"
        , "*.chs.h"
        , "*.dyn_o"
        , "*.dyn_hi"
        , "*.prof"
        , "*.aux"
        , "*.hp"
        , "*.eventlog"
        , ".virtualenv"
        , ".hsenv"
        , ".hpc"
        , ".cabal-sandbox/"
        , "cabal.sandbox.config"
        , "cabal.config"
        , "cabal.project.local"
        , ".ghc.environment.*"
        , ".HTF/"
        , ".hie/"
        , "# Stack"
        , ".stack-work/"
        , "stack.yaml.lock"
        , ""
        , "### IDE/support"
        , "# Vim"
        , "[._]*.s[a-v][a-z]"
        , "[._]*.sw[a-p]"
        , "[._]s[a-v][a-z]"
        , "[._]sw[a-p]"
        , "*~"
        , "tags"
        , ""
        , "# IntellijIDEA"
        , ".idea/"
        , ".ideaHaskellLib/"
        , "*.iml"
        , ""
        , "# Atom"
        , ".haskell-ghc-mod.json"
        , ""
        , "# VS"
        , ".vscode/"
        , ""
        , "# Emacs"
        , "*#"
        , ".dir-locals.el"
        , "TAGS"
        , ""
        , "# other"
        , ".DS_Store"
        ]

    -- additional .gitignore
    gitignoreCustom :: Text
    gitignoreCustom = if null settingsGitignore
        then ""
        else unlines ("\n# User specific" : settingsGitignore)

    ghActionsYml :: Text
    ghActionsYml = unlines $
        [ "name: CI"
        , ""
        , "# Trigger the workflow on push or pull request, but only for the master branch"
        , "on:"
        , "  pull_request:"
        , "  push:"
        , "    branches: [master]"
        , ""
        , "jobs:"
        , "  build:"
        , "    name: ghc ${{ matrix.ghc }}"
        , "    runs-on: ubuntu-16.04"
        , "    strategy:"
        , "      matrix:"
        , "        cabal: [" <> quote defaultCabal <> "]"
        , "        ghc:"
        ]
        <> map (indent 10 <>) ghActionsVersions
        <>
        [ ""
        , "    steps:"
        , "    - uses: actions/checkout@v2"
        , "      if: github.event.action == 'opened' || github.event.action == 'synchronize' || github.event.ref == 'refs/heads/master'"
        , ""
        , "    - uses: actions/setup-haskell@v1"
        , "      name: Setup Haskell"
        , "      with:"
        , "        ghc-version: ${{ matrix.ghc }}"
        , "        cabal-version: ${{ matrix.cabal }}"
        , ""
        , "    - uses: actions/cache@v1"
        , "      name: Cache ~/.cabal/store"
        , "      with:"
        , "        path: ~/.cabal/store"
        , "        key: ${{ runner.os }}-${{ matrix.ghc }}-cabal"
        , ""
        , "    - name: Build"
        , "      run: |"
        , "        " <> cabalUpdate
        , "        " <> cabalBuild
        , ""
        , "    - name: Test"
        , "      run: |"
        , "        " <> cabalTest
        ]


    ghActionsVersions :: [Text]
    ghActionsVersions = map
        (\ghc -> "- " <> quote (showGhcVer ghc))
        settingsTestedVersions

    -- create travis.yml template
    travisYml :: Text
    travisYml = unlines $
        [ "language: haskell"
        , ""
        , "git:"
        , "  depth: 5"
        , ""
        , "cabal: " <> quote defaultCabal
        , ""
        , "cache:"
        , "  directories:"
        ]
        <> travisCabalCache
        <> travisStackCache
        <>
        [ ""
        , "jobs:"
        , "  include:"
        ]
        <> travisCabalMtr
        <> travisStackMtr
        <> travisStackAllowFailuresMtr
        <> installAndScript
        <>
        [ ""
        , "notifications:"
        , "  email: false"
        ]

    travisCabalCache, travisStackCache :: [Text]
    travisCabalCache = memptyIfFalse settingsCabal ["  - " <> quote "$HOME/.cabal/store"]
    travisStackCache = memptyIfFalse settingsStack
        [ "  - " <> quote "$HOME/.stack"
        , "  - " <> quote "$TRAVIS_BUILD_DIR/.stack-work"
        ]

    travisCabalMtr :: [Text]
    travisCabalMtr = memptyIfFalse settingsCabal $
        map travisCabalMatrixItem settingsTestedVersions

    travisCabalMatrixItem :: GhcVer -> Text
    travisCabalMatrixItem (showGhcVer -> ghcV) = "  - ghc: " <> ghcV

    -- Due to the Stack issues with newer Cabal versions TravisCI for 'oldGhcs'
    -- can fail. Possible failure jobs are added to the @allow-failures@ section.
    travisStackMtr :: [Text]
    travisStackMtr = memptyIfFalse settingsStack $
        concatMap travisStackMatrixItem (delete defaultGHC settingsTestedVersions)
        <> travisStackMatrixDefaultItem

    travisStackAllowFailuresMtr :: [Text]
    travisStackAllowFailuresMtr = memptyIfFalse (settingsStack && not (null old)) $
        [ ""
        , "  allow_failures:"
        ]
        <> concatMap travisStackMatrixItem old
      where
        old :: [GhcVer]
        old = settingsTestedVersions `intersect` oldGhcs

    travisStackMatrixItem :: GhcVer -> [Text]
    travisStackMatrixItem (showGhcVer -> ghcV) =
        [ ""
        , "  - ghc: " <> ghcV
        , "    env: STACK_YAML=" <> quote ("$TRAVIS_BUILD_DIR/stack-" <> ghcV <> ".yaml")
        ]

    travisStackMatrixDefaultItem :: [Text]
    travisStackMatrixDefaultItem =
        [ ""
        , "  - ghc: " <> showGhcVer defaultGHC
        , "    env: STACK_YAML=" <> quote "$TRAVIS_BUILD_DIR/stack.yaml"
        ]

    installAndScript :: [Text]
    installAndScript =
        ""
        : "install:"
        : hlintCheck
        <>
        if settingsCabal
        then if settingsStack
             then installScriptBoth
             else installScriptCabal
        else installScriptStack

    installScriptBoth :: [Text]
    installScriptBoth =
        [ "  - |"
        , "    if [ -z " <> quote "$STACK_YAML" <> " ]; then"
        , "      " <> cabalUpdate
        , "      " <> cabalBuild
        , "    else"
        , "      curl -sSL https://get.haskellstack.org/ | sh"
        , "      stack --version"
        , "      " <> stackBuild
        , "    fi"
        , ""
        , "script:"
        , "  - |"
        , "    if [ -z " <> quote "$STACK_YAML" <> " ]; then"
        , "      " <> cabalTest
        , "    else"
        , "      " <> stackTest
        , "    fi"
        ]

    installScriptCabal :: [Text]
    installScriptCabal =
        [ "  - " <> cabalUpdate
        , "  - " <> cabalBuild
        , ""
        , "script:"
        , "  - " <> cabalTest
        ]

    installScriptStack :: [Text]
    installScriptStack =
        [ "  - curl -sSL https://get.haskellstack.org/ | sh"
        , "  - stack --version"
        , "  - " <> stackBuild
        , ""
        , "script:"
        , "  - " <> stackTest
        ]

    cabalUpdate :: Text
    cabalUpdate = "cabal v2-update"

    cabalBuild :: Text
    cabalBuild = "cabal v2-build --enable-tests --enable-benchmarks"

    cabalTest :: Text
    cabalTest = if settingsTest
        then "cabal v2-test --enable-tests --test-show-details=direct"
        else "echo 'No tests'"

    stackBuild :: Text
    stackBuild = "stack build --system-ghc --test --bench --no-run-tests --no-run-benchmarks --ghc-options=-Werror"

    stackTest :: Text
    stackTest = "stack test --system-ghc"

    hlintCheck :: [Text]
    hlintCheck =
        [ "  # HLint check"
        , "  - curl -sSL https://raw.github.com/ndmitchell/neil/master/misc/travis.sh | sh -s -- hlint ."
        , ""
        ]

    appVeyorYml :: Text
    appVeyorYml = unlines $
        if settingsCabal
        then appVeyorYmlCabal
        else appVeyorYmlStack

    appVeyorYmlCabal :: [Text]
    appVeyorYmlCabal = let defGhc = showGhcVer defaultGHC in
        [ "clone_folder: " <> quote "c:\\\\WORK"
        , "clone_depth: 5"
        , ""
        , "# Do not build feature branch with open Pull Requests"
        , "skip_branch_with_pr: true"
        , ""
        , "# build only master branch"
        , "branches:"
        , "  only:"
        , "    - master"
        , ""
        , "platform:"
        , "  - x86_64"
        , ""
        , "cache:"
        , "  - " <> quote "C:\\\\SR"
        , "  - dist-newstyle"
        , ""
        , "environment:"
        , "  global:"
        , "    CABOPTS: --store-dir=C:\\\\SR"
        , ""
        , "  matrix:"
        , "    - GHCVER: " <> defGhc
        , ""
        , "install:"
        , "  - choco source add -n mistuke -s https://www.myget.org/F/mistuke/api/v2"
        , "  - choco install -y cabal --version 2.4.1.0"
        , "  - choco install -y ghc   --version " <> defGhc
        , "  - refreshenv"
        , ""
        , "before_build:"
        , "  - cabal --version"
        , "  - ghc   --version"
        , "  - cabal %CABOPTS% v2-update"
        , ""
        , "build_script:"
        , "  - cabal %CABOPTS% v2-build --enable-tests"
        , "  - cabal %CABOPTS% v2-test  --enable-tests --test-show-details=direct"
        ]

    -- create appveyor.yml template
    appVeyorYmlStack :: [Text]
    appVeyorYmlStack =
        [ "clone_depth: 5"
        , ""
        , "# Do not build feature branch with open Pull Requests"
        , "skip_branch_with_pr: true"
        , ""
        , "# build only master branch"
        , "branches:"
        , "  only:"
        , "    - master"
        , ""
        , "environment:"
        , "  STACK_ROOT: C:\\sr"
        , "  STACK_VERSION: 2.1.1"
        , ""
        , "  # Workaround a gnarly bug https://github.com/haskell/cabal/issues/5386"
        , "  # See: https://www.fpcomplete.com/blog/2018/06/sed-a-debugging-story"
        , "  # TODO: check if it's fixed once we switch to lst-13 and GHC 8.6"
        , "  TMP: " <> quote "c:\\\\tmp"
        , ""
        , "  matrix:"
        , "    - STACK_YAML: stack.yaml"
        , ""
        , "cache:"
        , "  - " <> quote "%STACK_ROOT% -> %STACK_YAML%, appveyor.yml"
        , "  - " <> quote ".stack-work -> %STACK_YAML%, appveyor.yml"
        , ""
        , "install:"
        , "  - choco install -y haskell-stack --version %STACK_VERSION%"
        , "  - stack setup > nul"
        , ""
        , "build_script:"
        , "  - stack build --test --bench --no-run-tests --no-run-benchmarks --ghc-options=-Werror"
        , ""
        , "test_script:"
        , "  - stack test"
        ]
