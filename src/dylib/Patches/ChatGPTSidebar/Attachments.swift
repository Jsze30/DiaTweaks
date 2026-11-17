import Foundation

// Dia keeps the composer's attachment chips in Swift: each chip's controller has an attributes provider that knows its
// tab's URL. Mirror reads them without depending on Dia's symbols.

private func DPUnwrap(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else { return value }
    guard let child = mirror.children.first else { return nil }
    return DPUnwrap(child.value)
}

private func DPChild(_ value: Any?, _ label: String) -> Any? {
    guard let value = value.flatMap(DPUnwrap) else { return nil }
    var mirror: Mirror? = Mirror(reflecting: value)
    while let current = mirror {
        if let hit = current.children.first(where: { $0.label == label }) { return DPUnwrap(hit.value) }
        mirror = current.superclassMirror
    }
    return nil
}

private let DPAttachmentModules = ["Attachments.", "AttachmentDataSource.", "BoostCommandBar.", "SupertabAttachments."]

// The URL of every chip under `value`: whatever has an attributes provider with a URL.
private func DPCollectTabs(_ value: Any, _ depth: Int, _ seen: inout Set<ObjectIdentifier>, _ out: inout [URL]) {
    guard depth < 8, let value = DPUnwrap(value) else { return }
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .class {
        let id = ObjectIdentifier(value as AnyObject)
        guard !seen.contains(id) else { return }
        seen.insert(id)
    }
    if let url = DPChild(DPChild(value, "attributesProvider"), "url") as? URL {
        if !out.contains(url) { out.append(url) }
        return
    }
    let style = mirror.displayStyle
    let typeName = String(reflecting: type(of: value))
    let container = style == .collection || style == .dictionary || style == .set || style == .tuple
    guard container || DPAttachmentModules.contains(where: typeName.hasPrefix) else { return }
    for child in mirror.children {
        if let label = child.label, label.hasPrefix("_") || label.hasPrefix("$") || label == "delegate" || label == "subscriptions" { continue }
        DPCollectTabs(child.value, depth + 1, &seen, &out)
    }
}

// The web addresses of the tabs attached to the composer whose chip list is `list`.
@_cdecl("DPChatAttachedURLs")
public func DPChatAttachedURLs(_ list: AnyObject?) -> NSArray {
    let chips = DPChild(DPChild(list, "viewModel"), "delegate")
    var seen = Set<ObjectIdentifier>()
    var urls: [URL] = []
    for root in [chips, DPChild(chips, "delegate")].compactMap({ $0 }) { DPCollectTabs(root, 0, &seen, &urls) }
    return urls as NSArray
}
