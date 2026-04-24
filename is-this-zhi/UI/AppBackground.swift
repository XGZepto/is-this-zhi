//
//  AppBackground.swift
//  is-this-zhi
//
//  Created by Zepto on 23/4/2026.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct AppBackground: View {
    var body: some View {
        Color.groupedAppBackground
            .ignoresSafeArea()
    }
}

extension Color {
    static var groupedAppBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.clear
        #endif
    }
}

extension AnalysisVerdict {
    var displayTitle: String {
        switch self {
        case .suspected: "支語警報"
        case .borderline: "可疑邊緣"
        case .clear: "暫時安全"
        }
    }

    var badgeTitle: String {
        switch self {
        case .suspected: "抓到"
        case .borderline: "可疑"
        case .clear: "暫安"
        }
    }

    var badgeColor: Color {
        switch self {
        case .suspected: .red
        case .borderline: .orange
        case .clear: .green
        }
    }
}
