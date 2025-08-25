//
//  RevilioShortcuts.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import AppIntents

/// Revilio Shortcuts
struct RevilioShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .blue
    
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        
        // Text search shortcut
        AppShortcut(
            intent: FindTextIntent(),
            phrases: [
                "\(.applicationName) найти текст",
                "\(.applicationName) найти текст \(\.$query)",
                "\(.applicationName) искать текст \(\.$query)",
                "\(.applicationName) поиск текста \(\.$query)",
                
                "\(.applicationName) find text",
                "\(.applicationName) find text \(\.$query)",
                "\(.applicationName) search text \(\.$query)",
                
                "\(.applicationName) 查找文本",
                "\(.applicationName) 查找文本 \(\.$query)",
                "\(.applicationName) 搜索文本 \(\.$query)",
                "\(.applicationName) 文本搜索 \(\.$query)",
            ],
            shortTitle: "findTextShortTitle",
            systemImageName: "text.magnifyingglass"
        )
        
        // Item search shortcut
        AppShortcut(
            intent: FindItemIntent(),
            phrases: [
                "\(.applicationName) найти объект \(\.$item)",
                "\(.applicationName) поиск объекта \(\.$item)",
                "\(.applicationName) искать объект \(\.$item)",
                
                "\(.applicationName) find object \(\.$item)",
                "\(.applicationName) search object \(\.$item)",
                
                "\(.applicationName) 查找物体 \(\.$item)",
                "\(.applicationName) 物体搜索 \(\.$item)",
                "\(.applicationName) 搜索物体 \(\.$item)",
            ],
            shortTitle: "findItemShortTitle",
            systemImageName: "magnifyingglass"
        )

        // Text reading shortcut
        AppShortcut(
            intent: ReadTextIntent(),
            phrases: [
                "\(.applicationName) читай",
                "\(.applicationName) читать",
                "\(.applicationName) читай текст",
                "\(.applicationName) читать текст",
                
                "\(.applicationName) reading",
                "\(.applicationName) read text",
                
                "\(.applicationName) 阅读",
                "\(.applicationName) 读文本",
                "\(.applicationName) 阅读文本",
            ],
            shortTitle: "readTextShortTitle",
            systemImageName: "text.below.photo"
        )
    }
}
