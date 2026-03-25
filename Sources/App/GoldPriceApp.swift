import SwiftUI
import AppKit
import UserNotifications

@main
struct GoldPriceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusBarItem: NSStatusItem!
    private var statusBarController: StatusBarController!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            NSLog("[GoldPrice] App launched with bundle id: \(bundleIdentifier)")
            center.delegate = self
            center.getNotificationSettings { settings in
                NSLog("[GoldPrice] 当前通知设置: auth=\(settings.authorizationStatus.rawValue), alert=\(settings.alertSetting.rawValue), sound=\(settings.soundSetting.rawValue)")
            }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error = error {
                    NSLog("[GoldPrice] 通知权限请求失败: \(error.localizedDescription)")
                } else {
                    NSLog("[GoldPrice] 通知权限: \(granted)")
                }
            }
        } else {
            NSLog("[GoldPrice] 未检测到 bundleIdentifier，当前不是以 .app bundle 方式运行，系统通知不会弹出")
        }

        statusBarController = StatusBarController()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
