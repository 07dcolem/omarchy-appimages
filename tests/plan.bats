#!/usr/bin/env bats

load helpers/harness

setup() { harness_setup; }
teardown() { harness_teardown; }

plan_detail() {
  node --input-type=commonjs - "$REPO_ROOT/Model.js" "$1" <<'JS'
const fs = require("fs")
const vm = require("vm")
const src = fs.readFileSync(process.argv[2], "utf8").replace(/^\.pragma library\s*/, "")
const context = {}
vm.createContext(context)
vm.runInContext(src, context)
const data = JSON.parse(process.argv[3])
const plan = context.planFromInspect(data)
process.stdout.write(plan.detail)
JS
}

@test "plan: a filename version is labeled, including on an update" {
  detail=$(plan_detail '{"ok":true,"name":"Northwind","source":"/tmp/Northwind-2.4.1.AppImage","version":"2.4.1","versionSource":"filename","existing":false,"sameFile":false,"payloadConflict":false,"warning":""}')
  [ "$detail" = "Version 2.4.1 is from the filename." ]

  detail=$(plan_detail '{"ok":true,"name":"Same App","source":"/tmp/Same App-2.5.0.AppImage","version":"2.5.0","versionSource":"filename","oldVersion":"1.0","oldVersionSource":"desktop","existing":true,"sameFile":false,"payloadConflict":false,"target":"/home/u/Applications/Same App-2.5.0.AppImage","oldPayload":"/home/u/Applications/Old-1.0.AppImage","warning":""}')
  [ "$detail" = "Updates Same App from 1.0 to 2.5.0. The new version is from the filename. The previous file is removed." ]

  detail=$(plan_detail '{"ok":true,"name":"Same App","source":"/tmp/Same App-2.5.0.AppImage","version":"2.5.0","versionSource":"filename","oldVersion":"1.0","oldVersionSource":"filename","existing":true,"sameFile":false,"payloadConflict":false,"target":"/home/u/Applications/Same App-2.5.0.AppImage","oldPayload":"/home/u/Applications/Old-1.0.AppImage","warning":""}')
  [ "$detail" = "Updates Same App from 1.0 to 2.5.0. Both versions are from the filename. The previous file is removed." ]

  detail=$(plan_detail '{"ok":true,"name":"Same App","source":"/tmp/App-2.0.AppImage","version":"2.0","versionSource":"desktop","oldVersion":"1.0","oldVersionSource":"filename","existing":true,"sameFile":false,"payloadConflict":false,"target":"/home/u/Applications/App-2.0.AppImage","oldPayload":"/home/u/Applications/Old-1.0.AppImage","warning":""}')
  [ "$detail" = "Updates Same App from 1.0 to 2.0. The installed version is from the filename. The previous file is removed." ]
}

@test "plan: a desktop version is not labeled as a filename" {
  detail=$(plan_detail '{"ok":true,"name":"Same App","source":"/tmp/App-2.0.AppImage","version":"2.0","versionSource":"desktop","oldVersion":"1.0","oldVersionSource":"desktop","existing":true,"sameFile":false,"payloadConflict":false,"target":"/home/u/Applications/App-2.0.AppImage","oldPayload":"/home/u/Applications/App-1.0.AppImage","warning":""}')
  [ "$detail" = "Updates Same App from 1.0 to 2.0. The previous file is removed." ]

  detail=$(plan_detail '{"ok":true,"name":"Foo","source":"/tmp/Foo.AppImage","version":"3.0","versionSource":"desktop","existing":false,"sameFile":false,"payloadConflict":false,"warning":""}')
  [ "$detail" = "" ]
}

@test "plan: the reader reason is shown on an update" {
  detail=$(plan_detail '{"ok":true,"name":"Same App","source":"/tmp/Same App.AppImage","version":"","versionSource":"","oldVersion":"1.0","oldVersionSource":"desktop","existing":true,"sameFile":false,"payloadConflict":false,"target":"/home/u/Applications/Same App.AppImage","oldPayload":"/home/u/Applications/Old.AppImage","warning":"This is a type-1 AppImage. Confirm shows the filename."}')
  [ "$detail" = "Updates Same App (1.0). The previous file is removed. This is a type-1 AppImage. Confirm shows the filename." ]

  detail=$(plan_detail '{"ok":true,"name":"Fat","source":"/tmp/Fat.AppImage","version":"","versionSource":"","existing":false,"sameFile":false,"payloadConflict":false,"warning":"The embedded filesystem size is out of range. Confirm shows the filename."}')
  [ "$detail" = "The embedded filesystem size is out of range. Confirm shows the filename." ]

  detail=$(plan_detail '{"ok":true,"name":"Odd","source":"/tmp/Odd.AppImage","version":"","versionSource":"","existing":false,"sameFile":false,"payloadConflict":false,"warning":"This file is not a type-2 AppImage. Confirm shows the filename."}')
  [ "$detail" = "This file is not a type-2 AppImage. Confirm shows the filename." ]

  detail=$(plan_detail '{"ok":true,"name":"Empty","source":"/tmp/Empty.AppImage","version":"","versionSource":"","existing":false,"sameFile":false,"payloadConflict":false,"warning":"This AppImage has no root desktop entry. Confirm shows the filename."}')
  [ "$detail" = "This AppImage has no root desktop entry. Confirm shows the filename." ]
}
