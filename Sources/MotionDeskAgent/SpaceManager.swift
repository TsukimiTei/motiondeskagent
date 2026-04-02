import AppKit

// MARK: - Private CGS API declarations

/// 私有 CGS 连接 ID 类型
typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64

/// 获取主连接 ID
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

/// 获取所有 Space 的 ID 列表
@_silgen_name("CGSCopySpaces")
func CGSCopySpaces(_ cid: CGSConnectionID, _ mask: Int) -> CFArray

/// 获取当前活跃的 Space ID
@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

/// 将窗口移动到指定 Space
@_silgen_name("CGSMoveWindowsToManagedSpace")
func CGSMoveWindowsToManagedSpace(_ cid: CGSConnectionID, _ windows: CFArray, _ space: CGSSpaceID)

// Space mask 常量
private let kCGSAllSpacesMask = 7       // 所有类型的 space
private let kCGSUserSpacesMask = 1      // 仅用户创建的桌面

/// 管理 macOS 虚拟桌面（Space）
class SpaceManager {

    /// 获取所有用户桌面的 Space ID 列表
    static func getUserSpaces() -> [CGSSpaceID] {
        let conn = CGSMainConnectionID()
        guard let spacesRef = CGSCopySpaces(conn, kCGSUserSpacesMask) as? [NSNumber] else {
            return []
        }
        return spacesRef.map { CGSSpaceID($0.uint64Value) }
    }

    /// 获取当前活跃桌面的 Space ID
    static func getActiveSpace() -> CGSSpaceID {
        return CGSGetActiveSpace(CGSMainConnectionID())
    }

    /// 获取桌面信息列表（编号 + Space ID）
    static func getSpaceList() -> [(index: Int, spaceId: CGSSpaceID, isCurrent: Bool)] {
        let spaces = getUserSpaces()
        let activeSpace = getActiveSpace()
        return spaces.enumerated().map { (idx, sid) in
            (index: idx + 1, spaceId: sid, isCurrent: sid == activeSpace)
        }
    }

    /// 将窗口移动到指定 Space
    static func moveWindow(_ window: NSWindow, toSpace spaceId: CGSSpaceID) {
        let conn = CGSMainConnectionID()
        let windowNumber = window.windowNumber
        let windowArray = [NSNumber(value: windowNumber)] as CFArray
        CGSMoveWindowsToManagedSpace(conn, windowArray, spaceId)
    }

    /// 设置窗口是否显示在所有桌面
    static func setWindowOnAllSpaces(_ window: NSWindow, allSpaces: Bool) {
        if allSpaces {
            window.collectionBehavior.insert(.canJoinAllSpaces)
        } else {
            window.collectionBehavior.remove(.canJoinAllSpaces)
        }
    }
}
