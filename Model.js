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
