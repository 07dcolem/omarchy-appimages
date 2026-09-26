.pragma library

function isAppImagePath(path) {
  var text = String(path || "")
  if (!text || text.charAt(text.length - 1) === "/") return false
  return /\.appimage$/i.test(text)
}

function fileUrlToPath(value) {
  var text = String(value || "").trim()
  if (text.slice(0, 7) === "file://") {
    var rest = text.slice(7)
    var slash = rest.indexOf("/")
    if (slash > 0) rest = rest.slice(slash)
    try { return decodeURIComponent(rest) } catch (e) { return rest }
  }
  if (text.charAt(0) === "/") return text
  return ""
}

function baseName(path) {
  var parts = String(path || "").split("/")
  return parts.length ? parts[parts.length - 1] : ""
}

function destination(home, path) {
  var root = String(home || "")
  if (root.charAt(root.length - 1) === "/") root = root.slice(0, -1)
  return root + "/Applications/" + baseName(path)
}

function parseList(text) {
  try {
    var data = JSON.parse(String(text || ""))
    if (!data || !Array.isArray(data.apps))
      return { ok: false, fuse: true, apps: [], error: "Could not read installed AppImages" }
    return { ok: true, fuse: data.fuse !== false, apps: data.apps, error: "" }
  } catch (e) {
    return { ok: false, fuse: true, apps: [], error: "Could not read installed AppImages" }
  }
}

function fileUrl(path) {
  var text = String(path || "")
  if (!text) return ""
  return "file://" + encodeURI(text)
}

function clip(value, max) {
  var text = String(value == null ? "" : value)
  if (text.length > max) return text.slice(0, max)
  return text
}

function parseInspect(text) {
  var lines = String(text || "").split("\n")
  var line = ""
  for (var i = lines.length - 1; i >= 0; i--) {
    var candidate = lines[i].replace(/^\s+|\s+$/g, "")
    if (candidate.length && candidate.charAt(0) === "{") {
      line = candidate
      break
    }
  }
  if (!line) return { ok: false }
  try {
    var data = JSON.parse(line)
    if (!data || data.ok !== true || typeof data.name !== "string" || typeof data.source !== "string")
      return { ok: false }
    return data
  } catch (e) {
    return { ok: false }
  }
}

function planFromInspect(data) {
  var install = {
    replace: false,
    enabled: true,
    title: "Install this AppImage?",
    detail: "",
    note: "Install moves the file into Applications.",
    button: "Install"
  }
  if (!data || data.ok !== true) return install

  var name = clip(data.name, 120)

  if (data.payloadConflict === true) {
    return {
      replace: false,
      enabled: false,
      title: "Cannot install this file",
      detail: "That destination is already used by another installed AppImage.",
      note: "Rename the file, or remove the app that uses it.",
      button: "Install"
    }
  }

  if (data.sameFile === true && data.existing === true) {
    return {
      replace: false,
      enabled: false,
      title: "Already installed",
      detail: (name || "This app") + " is already this file.",
      note: "",
      button: "Install"
    }
  }

  if (data.existing === true) {
    var oldVersion = clip(data.oldVersion, 80)
    var newVersion = clip(data.version, 80)
    var subject = name || "the installed app"
    var detail = "Updates " + subject + "."
    if (oldVersion && newVersion) detail = "Updates " + subject + " from " + oldVersion + " to " + newVersion + "."
    else if (newVersion) detail = "Updates " + subject + " to " + newVersion + "."
    else if (oldVersion) detail = "Updates " + subject + " (" + oldVersion + ")."
    if (data.oldPayload && data.target && data.oldPayload === data.target)
      detail += " The file in Applications is replaced."
    else
      detail += " The previous file is removed."
    return {
      replace: true,
      enabled: true,
      title: "Update this AppImage?",
      detail: detail,
      note: "Update replaces the installed launcher.",
      button: "Update"
    }
  }

  return install
}
