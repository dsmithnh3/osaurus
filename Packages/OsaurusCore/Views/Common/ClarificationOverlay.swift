//
//  ClarificationOverlay.swift
//  osaurus
//
//  Reusable overlay for clarification requests during work execution.
//

import SwiftUI

struct ClarificationOverlay: View {
    let request: ClarificationRequest
    let onSubmit: (String) -> Void

    @Environment(\.theme) private var theme
    @State private var isAppearing = false

    var body: some View {
        VStack {
            Spacer()

            ClarificationCardView(request: request, onSubmit: onSubmit)
                .opacity(isAppearing ? 1 : 0)
                .offset(y: isAppearing ? 0 : 30)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .onAppear {
            withAnimation(theme.springAnimation()) {
                isAppearing = true
            }
        }
    }
}
