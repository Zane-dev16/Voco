//
//  TranslationModel+UI.swift
//  Voco
//
//  UI-facing extensions for TranslationModel. Kept separate to avoid
//  pulling SwiftUI into the core model definition.
//

import SwiftUI

extension TranslationModel {
    var providerColor: Color {
        switch provider {
        case "Tencent": return .blue
        case "Qwen": return .purple
        case "Meta": return .indigo
        case "Google": return .teal
        default: return .gray
        }
    }

    var providerIcon: String {
        switch provider {
        case "Tencent": return "bubble.left.fill"
        case "Qwen": return "sparkles"
        case "Meta": return "cube.fill"
        case "Google": return "globe"
        default: return "cpu"
        }
    }

    var speedRating: String {
        switch quantization {
        case "1.25-bit STQ1_0", "Q8_0": return "Fast"
        case "Q4_K_M", "IQ3_M", "IQ3_S": return "Balanced"
        case "IQ2_XXS": return "Compact"
        default: return "Standard"
        }
    }

    var qualityRating: String {
        switch quantization {
        case "1.25-bit STQ1_0", "IQ2_XXS": return "Compact"
        case "Q4_K_M", "IQ3_M", "IQ3_S": return "High"
        case "Q8_0": return "Maximum"
        default: return "Standard"
        }
    }
}
